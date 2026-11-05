import Testing
import Foundation
@testable import swift_similarity

private func extract(_ source: String, _ configuration: CodeElementExtractor.Configuration) throws -> [CodeElement] {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ExtractionFilter-\(UUID().uuidString).swift")
    try source.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    return try CodeElementExtractor(configuration: configuration).extractElements(from: url.path)
}

private func names(_ elements: [CodeElement]) -> Set<String> {
    Set(elements.map(\.name))
}

@Test("minLines skips short declarations")
func testMinLinesFilter() throws {
    let source = """
    func oneLiner() { print(1) }
    func threeLines() {
        print(1)
    }
    func fiveLines() {
        let a = 1
        let b = 2
        print(a + b)
    }
    """
    #expect(names(try extract(source, .init(elementTypes: [.function]))) == ["oneLiner", "threeLines", "fiveLines"])
    #expect(names(try extract(source, .init(elementTypes: [.function], minLines: 3))) == ["threeLines", "fiveLines"])
    #expect(names(try extract(source, .init(elementTypes: [.function], minLines: 5))) == ["fiveLines"])
}

@Test("minTokens counts the compared syntax")
func testMinTokensFilter() throws {
    let source = """
    func small() { print(1) }
    func large(value: Int) -> Int { let doubled = value * 2; return doubled + 1 }
    """
    // `func small() { print(1) }` has 10 tokens, its body `{ print(1) }` has 6.
    #expect(names(try extract(source, .init(elementTypes: [.function], minTokens: 10))) == ["small", "large"])
    #expect(names(try extract(source, .init(elementTypes: [.function], minTokens: 11))) == ["large"])
    #expect(names(try extract(source, .init(elementTypes: [.function], minTokens: 6, compareBodyOnly: true))) == ["small", "large"])
    #expect(names(try extract(source, .init(elementTypes: [.function], minTokens: 7, compareBodyOnly: true))) == ["large"])
}

@Test("similarity-ignore comments skip the following declaration")
func testIgnoreDirective() throws {
    let source = """
    // similarity-ignore
    func lineComment() { print(1) }

    /* similarity-ignore: generated */
    func blockComment() { print(1) }

    /// Documented.
    /// similarity-ignore
    @discardableResult
    func withAttribute() -> Int { 1 }

    // similarity-ignore
    struct Ignored {
        func nested() { print(1) }
    }

    // A regular comment
    func kept() { print(1) }

    func trailing() { print(1) } // similarity-ignore
    func afterTrailing() { print(1) }
    """
    let all = CodeElementExtractor.Configuration(respectIgnoreDirectives: false)
    #expect(names(try extract(source, all)).count == 8)

    // Only the marked declaration is skipped, not the declarations nested in it. A comment at
    // the end of the previous line belongs to that line, not to the next declaration.
    #expect(names(try extract(source, .init())) == ["nested", "kept", "trailing", "afterTrailing"])
}

@Test("compareBodyOnly compares only bodies")
func testCompareBodyOnly() throws {
    let source = """
    protocol Shape {
        func area() -> Double
    }
    struct Square {
        let side: Double
        func area() -> Double { side * side }
    }
    """
    let whole = try extract(source, .init())
    let bodies = try extract(source, .init(compareBodyOnly: true))

    // A protocol requirement has no body and is skipped.
    #expect(whole.filter { $0.name == "area" }.count == 2)
    #expect(bodies.filter { $0.name == "area" }.count == 1)

    let functionBody = try #require(bodies.first { $0.name == "area" })
    #expect(functionBody.treeNode.label == "CodeBlock")
    let typeBody = try #require(bodies.first { $0.name == "Square" })
    #expect(typeBody.treeNode.label == "MemberBlock")
    // Locations still cover the whole declaration.
    #expect(functionBody.startLine == 6 && functionBody.endLine == 6)
    #expect(typeBody.startLine == 4 && typeBody.endLine == 7)
}

@Test("compareBodyOnly ignores signature differences")
func testCompareBodyOnlyIgnoresSignatures() throws {
    let source = """
    func first(a: Int, b: Int) async throws -> Int {
        let sum = a + b
        return sum * 2
    }
    @MainActor public func second(_ x: [String: Int]) -> Int {
        let sum = a + b
        return sum * 2
    }
    """
    let calculator = SimilarityCalculator()
    let whole = try extract(source, .init())
    let bodies = try extract(source, .init(compareBodyOnly: true))
    let wholeScore = calculator.calculateSimilarity(between: whole[0].treeNode, and: whole[1].treeNode).similarityScore
    let bodyScore = calculator.calculateSimilarity(between: bodies[0].treeNode, and: bodies[1].treeNode).similarityScore
    #expect(wholeScore < 1.0)
    #expect(bodyScore == 1.0)
}
