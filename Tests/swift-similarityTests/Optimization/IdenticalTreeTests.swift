import Testing
@testable import swift_similarity

// MARK: - Helpers

/// Elements with many copies of the same trees (like generated code). Element 0 spans its whole
/// file, so every other element of that file is nested in it, including copies of its own tree.
private func elementsWithCopies(count: Int, seed: UInt64) -> [CodeElement] {
    var rng = SplitMix64(seed: seed)
    let labels = ["a", "b", "c", "d"]
    let pool = (0..<6).map { _ in randomTree(size: Int.random(in: 1...10, using: &rng), labels: labels, using: &rng) }
    return (0..<count).map { index in
        let tree = Int.random(in: 0..<10, using: &rng) < 7
            ? pool.randomElement(using: &rng)!
            : randomTree(size: Int.random(in: 1...10, using: &rng), labels: labels, using: &rng)
        let byteRange = index == 0 ? 0..<1_000_000 : (index * 100)..<(index * 100 + 50)
        return CodeElement(
            elementType: .function, name: "f\(index)", signature: "f\(index)", filePath: "/file\(index % 3).swift",
            startLine: index + 1, endLine: index + 1, codePreview: "", treeNode: tree, byteRange: byteRange
        )
    }
}

/// Every pair at or above the threshold by brute force, in the scanner's order: most similar
/// first, ties by position.
private func bruteForce(_ elements: [CodeElement], threshold: Double) -> [(Int, Int, Double)] {
    var pairs: [(Int, Int, Double)] = []
    for i in 0..<elements.count {
        for j in (i + 1)..<elements.count where !elements[i].isNested(with: elements[j]) {
            let score = SimilarityCalculator().calculateSimilarity(between: elements[i].treeNode, and: elements[j].treeNode).similarityScore
            if score >= threshold {
                pairs.append((i, j, score))
            }
        }
    }
    return pairs.sorted { ($1.2, $0.0, $0.1) < ($0.2, $1.0, $1.1) }
}

private func indexed(_ pairs: [SimilarityScanner.Pair]) -> [(Int, Int, Double)] {
    pairs.map { (Int($0.first.name.dropFirst())!, Int($0.second.name.dropFirst())!, $0.similarity) }
}

private func same(_ a: [(Int, Int, Double)], _ b: [(Int, Int, Double)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && abs($0.2 - $1.2) < 1e-12 }
}

// MARK: - Tests

@Test("Comparing one tree per class of copies gives exactly the brute-force pairs, scores and order", arguments: [UInt64(1), 2, 3])
func testIdenticalClassesAreExact(seed: UInt64) async throws {
    let elements = elementsWithCopies(count: 40, seed: seed)
    for threshold in [0.0, 0.5, 0.8, 1.0] {
        let result = try await SimilarityScanner(maxConcurrency: 4).scan(elements, threshold: threshold)
        #expect(same(indexed(result.pairs), bruteForce(elements, threshold: threshold)))
        let stats = result.statistics
        #expect(stats.nestedPairs + stats.pairsRuledOutByUpperBound + stats.pairsCompared + stats.identicalPairs == stats.totalPairs)
        #expect(stats.distinctTreeCount < elements.count)
        #expect(stats.identicalPairs > 0)
        #expect(stats.similarPairs == result.pairs.count)
        #expect(result.matchingPairCount == result.pairs.count)
    }
}

@Test("Copies nested in each other are not reported")
func testNestedCopiesAreSkipped() async throws {
    let tree = SimpleTreeNode(label: "a", children: [SimpleTreeNode(label: "b")])
    func element(_ name: String, _ range: Range<Int>) -> CodeElement {
        CodeElement(elementType: .function, name: name, signature: name, filePath: "/f.swift", startLine: 1, endLine: 1, codePreview: "", treeNode: tree, byteRange: range)
    }
    let elements = [element("outer", 0..<100), element("inner", 10..<20), element("other", 200..<210)]
    let result = try await SimilarityScanner().scan(elements, threshold: 1.0)
    #expect(Set(result.pairs.map { "\($0.first.name)/\($0.second.name)" }) == ["outer/other", "inner/other"])
    #expect(result.statistics.nestedPairs == 1)
    #expect(result.statistics.identicalPairs == 2)
    #expect(result.statistics.distinctTreeCount == 1)
}

@Test("maxPairs keeps the first pairs of the full result and still counts them all")
func testMaxPairs() async throws {
    let elements = elementsWithCopies(count: 40, seed: 9)
    let scanner = SimilarityScanner()
    let all = try await scanner.scan(elements, threshold: 0.5)
    #expect(all.pairs.count > 50)
    for limit in [0, 1, 7, 50, all.pairs.count, all.pairs.count + 10] {
        let limited = try await scanner.scan(elements, threshold: 0.5, maxPairs: limit)
        #expect(same(indexed(limited.pairs), Array(indexed(all.pairs).prefix(limit))))
        #expect(limited.matchingPairCount == all.pairs.count)
        #expect(limited.omittedPairCount == max(0, all.pairs.count - limit))
        #expect(limited.statistics.similarPairs == all.statistics.similarPairs)
    }
}

@Test("The pair predicate selects pairs before maxPairs counts them")
func testPredicateBeforeLimit() async throws {
    let elements = elementsWithCopies(count: 40, seed: 5)
    let scanner = SimilarityScanner()
    let all = try await scanner.scan(elements, threshold: 0.5)
    let filter = PairFilter(nameContains: "f1")
    let expected = indexed(filter.apply(to: all.pairs))
    #expect(!expected.isEmpty && expected.count < all.pairs.count)

    let filtered = try await scanner.scan(elements, threshold: 0.5, including: filter.predicate)
    #expect(same(indexed(filtered.pairs), expected))
    #expect(filtered.matchingPairCount == expected.count)
    #expect(filtered.statistics.similarPairs == all.pairs.count)

    let limited = try await scanner.scan(elements, threshold: 0.5, maxPairs: 3, including: filter.predicate)
    #expect(same(indexed(limited.pairs), Array(expected.prefix(3))))
    #expect(limited.matchingPairCount == expected.count)
}

@Test("The member scanner applies maxPairs and the predicate too")
func testMemberScannerLimit() {
    func type(_ name: String, line: Int) -> CodeElement {
        CodeElement(
            elementType: .struct, name: name, signature: name, filePath: "/t.swift", startLine: line, endLine: line,
            codePreview: "", treeNode: SimpleTreeNode(label: name), byteRange: line * 100..<(line * 100 + 10),
            members: [TypeMember(kind: .property, name: "id", type: "Int"), TypeMember(kind: .property, name: "name", type: "String")]
        )
    }
    let elements = (0..<5).map { type("T\($0)", line: $0) }
    let all = MemberSimilarityScanner().scan(elements, threshold: 0.9)
    #expect(all.pairs.count == 10)
    let limited = MemberSimilarityScanner().scan(elements, threshold: 0.9, maxPairs: 4, including: { a, _ in a.name != "T0" })
    #expect(limited.matchingPairCount == 6)
    #expect(limited.pairs.map { "\($0.first.name)/\($0.second.name)" } == ["T1/T2", "T1/T3", "T1/T4", "T2/T3"])
}

@Test("max_pairs is read from the config file and defaults to a limit")
func testMaxPairsSetting() throws {
    #expect(try SimilarityConfig.parse("max_pairs = 0").maxPairs == 0)
    #expect(ScanSettings.resolve(commandLine: SimilarityConfig(), file: nil).maxPairs == ScanSettings.defaultMaxPairs)
    #expect(ScanSettings.resolve(commandLine: SimilarityConfig(maxPairs: 5), file: SimilarityConfig(maxPairs: 0)).maxPairs == 5)
}

@Test("The member scanner gives the same result with a limited number of tasks")
func testMemberScannerConcurrencyLimit() {
    func type(_ name: String, line: Int, fields: Int) -> CodeElement {
        CodeElement(
            elementType: .struct, name: name, signature: name, filePath: "/t.swift", startLine: line, endLine: line,
            codePreview: "", treeNode: SimpleTreeNode(label: name), byteRange: line * 100..<(line * 100 + 10),
            members: (0..<fields).map { TypeMember(kind: .property, name: "f\($0)", type: "Int") }
        )
    }
    let elements = (0..<20).map { type("T\($0)", line: $0, fields: 2 + $0 % 3) }
    let all = MemberSimilarityScanner().scan(elements, threshold: 0.6)
    for maxConcurrency in [1, 3, 64] {
        let scanner = MemberSimilarityScanner(maxConcurrency: maxConcurrency)
        let limited = scanner.scan(elements, threshold: 0.6)
        #expect(scanner.workerCount == maxConcurrency)
        #expect(limited.statistics.workerCount == maxConcurrency)
        #expect(limited.pairs.map { "\($0.first.name)/\($0.second.name)/\($0.similarity)" } == all.pairs.map { "\($0.first.name)/\($0.second.name)/\($0.similarity)" })
        #expect(limited.statistics.pairsCompared == all.statistics.pairsCompared)
    }
}

@Test("concurrentMap keeps the order of the elements with a concurrency limit")
func testConcurrentMapLimit() {
    let numbers = Array(0..<1000)
    for maxConcurrency in [0, 1, 7, 2000] {
        #expect(numbers.concurrentMap(maxConcurrency: maxConcurrency) { $0 * 2 } == numbers.map { $0 * 2 })
    }
    #expect([Int]().concurrentMap(maxConcurrency: 4) { $0 }.isEmpty)
}
