import Testing
import Foundation
@testable import swift_similarity

// MARK: - Similarity Scanner Tests

@Test("Scanner finds exactly the pairs a brute-force TSED scan finds")
func testScannerMatchesBruteForce() async throws {
    let elements = createTestElements(count: 20)
    let threshold = 0.4
    
    var expected: [String: Double] = [:]
    for i in 0..<elements.count {
        for j in (i + 1)..<elements.count where !elements[i].isNested(with: elements[j]) {
            let score = SimilarityCalculator()
                .calculateSimilarity(between: elements[i].treeNode, and: elements[j].treeNode)
                .similarityScore
            if score >= threshold {
                expected["\(i)-\(j)"] = score
            }
        }
    }
    
    let index = Dictionary(uniqueKeysWithValues: elements.enumerated().map { ("\($1.filePath):\($1.startLine):\($1.name)", $0) })
    func key(_ element: CodeElement) -> Int { index["\(element.filePath):\(element.startLine):\(element.name)"]! }
    var actual: [String: Double] = [:]
    for (element1, element2, score) in try await SimilarityScanner().findSimilarPairs(in: elements, threshold: threshold) {
        #expect(key(element1) < key(element2))
        actual["\(key(element1))-\(key(element2))"] = score
    }
    
    #expect(actual == expected)
}

@Test("Statistics account for every pair once")
func testScannerStatistics() async throws {
    let elements = createTestElements(count: 30)
    let result = try await SimilarityScanner(maxConcurrency: 3).scan(elements, threshold: 0.5)
    let stats = result.statistics
    
    #expect(stats.elementCount == 30)
    #expect(stats.totalPairs == 30 * 29 / 2)
    #expect(stats.nestedPairs + stats.pairsRuledOutByUpperBound + stats.pairsCompared == stats.totalPairs)
    #expect(stats.similarPairs == result.pairs.count)
    #expect(stats.similarPairs <= stats.pairsCompared)
    #expect(stats.workerCount == 3)
    #expect(stats.fingerprintTime >= 0 && stats.comparisonTime >= 0)
}

@Test("Progress reaches the end of both phases")
func testScannerProgress() async throws {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [SimilarityScanner.Progress] = []
        func record(_ progress: SimilarityScanner.Progress) { lock.withLock { events.append(progress) } }
        var all: [SimilarityScanner.Progress] { lock.withLock { events } }
    }
    let recorder = Recorder()
    let elements = createTestElements(count: 40)
    let result = try await SimilarityScanner(progressHandler: recorder.record).scan(elements, threshold: 0.3)
    
    let fingerprinting = recorder.all.filter { $0.phase == .fingerprinting }
    let comparing = recorder.all.filter { $0.phase == .comparing }
    #expect(fingerprinting.last?.completed == elements.count)
    #expect(fingerprinting.last?.completionPercentage == 100)
    #expect(comparing.first?.completed == 0)
    #expect(comparing.last?.completionPercentage == 100)
    #expect(comparing.last?.pairsFound == result.pairs.count)
}

@Test("Results shrink as the threshold rises")
func testScannerThresholdMonotonicity() async throws {
    let elements = createTestElements(count: 50)
    let scanner = SimilarityScanner()
    
    var previousCount = Int.max
    for threshold in [0.3, 0.4, 0.5] {
        let pairs = try await scanner.findSimilarPairs(in: elements, threshold: threshold)
        #expect(pairs.count <= previousCount)
        #expect(pairs.allSatisfy { $0.similarity >= threshold && $0.similarity <= 1.0 })
        previousCount = pairs.count
    }
}

@Test("Edge cases: fewer than two elements, extreme thresholds")
func testScannerEdgeCases() async throws {
    let scanner = SimilarityScanner()
    
    let empty = try await scanner.scan([], threshold: 0.3)
    #expect(empty.pairs.isEmpty)
    #expect(empty.statistics.totalPairs == 0)
    
    let single = try await scanner.scan(createTestElements(count: 1), threshold: 0.3)
    #expect(single.pairs.isEmpty)
    #expect(single.statistics.totalPairs == 0)
    
    let two = try await scanner.findSimilarPairs(in: createTestElements(count: 2), threshold: 0.1)
    #expect(two.count <= 1)
    
    // Threshold 0 reports every pair (none of the test elements are nested)
    let elements = createTestElements(count: 10)
    #expect(try await scanner.findSimilarPairs(in: elements, threshold: 0.0).count == 45)
    #expect(try await scanner.findSimilarPairs(in: elements, threshold: 1.0).allSatisfy { $0.similarity == 1.0 })
}

// MARK: - Test Helpers

private func createTestElements(count: Int) -> [CodeElement] {
    var elements: [CodeElement] = []
    
    for i in 0..<count {
        // Create a simple tree node for testing
        let treeNode = SimpleTreeNode(
            label: "Function:\(i)",
            children: [
                SimpleTreeNode(label: "Parameters", children: []),
                SimpleTreeNode(label: "CodeBlock", children: [])
            ]
        )
        
        let element = CodeElement(
            elementType: .function,
            name: "testElement\(i)",
            signature: "func testElement\(i)()",
            filePath: "test\(i % 3).swift",
            startLine: i * 10 + 1,
            endLine: i * 10 + 5,
            codePreview: "func testElement\(i)() { }",
            treeNode: treeNode
        )
        
        elements.append(element)
    }
    
    return elements
} 
@Test("Tasks cover every pair exactly once, heaviest rows first", arguments: [
    ([5, 4, 3, 2, 1], 1),
    ([100, 90, 3, 2, 2, 1, 1, 1], 4),
    ([7], 2),
    (Array(repeating: 10, count: 40), 12),
])
func testPairTasksCoverAllPairs(sizes: [Int], workerCount: Int) {
    let tasks = SimilarityScanner.makeTasks(sizes: sizes, workerCount: workerCount)
    var seen = Set<[Int]>()
    for task in tasks {
        for position in task.positions {
            #expect(task.row < position)
            #expect(seen.insert([task.row, position]).inserted)
        }
    }
    #expect(seen.count == sizes.count * (sizes.count - 1) / 2)
    #expect(tasks.map(\.row) == tasks.map(\.row).sorted())
}

@Test("Results are sorted by score and do not depend on scheduling")
func testScannerStableOrder() async throws {
    let source = """
    func a(_ x: Int) -> Int { return x + 1 }
    func b(_ y: Int) -> Int { return y + 2 }
    func c(_ z: Int) -> Int { let w = z * 2; return w + 3 }
    func d(_ v: [Int]) -> Int { var total = 0; for item in v { total += item }; return total }
    func e(_ v: [Int]) -> Int { var sum = 0; for item in v { sum += item * 2 }; return sum }
    struct S { let a: Int; let b: Int }
    struct T { let c: Int; let d: Int }
    """
    let elements = try extractElements(from: source)
    
    func describe(_ results: [SimilarityScanner.Pair]) -> [String] {
        results.map { "\($0.0.name)-\($0.1.name)-\($0.2)" }
    }
    let reference = describe(try await SimilarityScanner(maxConcurrency: 1)
        .findSimilarPairs(in: elements, threshold: 0.2))
    #expect(!reference.isEmpty)
    for _ in 0..<5 {
        let results = try await SimilarityScanner(maxConcurrency: 8)
            .findSimilarPairs(in: elements, threshold: 0.2)
        #expect(describe(results) == reference)
        #expect(results.map(\.2) == results.map(\.2).sorted(by: >))
    }
}
