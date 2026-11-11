import Testing
import Foundation
import SwiftSyntax
@testable import swift_similarity

// MARK: - Helpers

private func fingerprint(of tree: TreeNode) -> ASTNodeFingerprint {
    var counts: [String: Int] = [:]
    var total = 0
    func visit(_ node: TreeNode) {
        counts[node.label, default: 0] += 1
        total += 1
        node.children.forEach(visit)
    }
    visit(tree)
    return ASTNodeFingerprint(nodeTypeCounts: counts, totalNodes: total, maxDepth: 0, leafNodeCount: 0)
}

private func element(_ source: String, name: String) -> CodeElement {
    let file = SwiftASTParser.parseSource(source)
    let function = file.statements.first!.item.as(FunctionDeclSyntax.self)!
    return CodeElement(
        elementType: .function,
        name: name,
        signature: source,
        filePath: "/test/\(name).swift",
        startLine: 1,
        endLine: 1,
        codePreview: source,
        treeNode: ASTToTreeConverter.convertSyntaxNode(function)
    )
}

private let sources = [
    ("sum", "func sum(a: Int, b: Int) -> Int { let total = a + b; return total }"),
    ("add", "func add(x: Int, y: Int) -> Int { let result = x + y; return result }"),
    ("clamp", "func clamp(v: Int) -> Int { if v > 10 { return 10 } ; if v < 0 { return 0 } ; return v }"),
    ("greet", "func greet(name: String) { print(\"Hello, \\(name)\") }"),
]

// MARK: - Bound

@Test("TSED upper bound never underestimates the real TSED", arguments: [
    APTED.OperationCosts(),
    APTED.OperationCosts(insertion: 0.8, deletion: 1.0, substitution: 1.0),
    APTED.OperationCosts(insertion: 1.0, deletion: 2.0, substitution: 3.0),
])
func testUpperBoundIsSound(costs: APTED.OperationCosts) {
    var rng = SplitMix64(seed: 7)
    let calculator = SimilarityCalculator(configuration: .init(aptedCosts: costs))
    for _ in 0..<300 {
        let tree1 = randomTree(size: Int.random(in: 1...12, using: &rng), labels: ["a", "b", "c", "d"], using: &rng)
        let tree2 = randomTree(size: Int.random(in: 1...12, using: &rng), labels: ["a", "b", "c", "d"], using: &rng)
        let tsed = calculator.calculateSimilarity(between: tree1, and: tree2).similarityScore
        let bound = fingerprint(of: tree1).tsedUpperBound(to: fingerprint(of: tree2), costs: costs)
        #expect(bound >= tsed - 1e-9)
    }
}

@Test("Upper bound rejects trees with very different label histograms")
func testUpperBoundRejects() {
    let small = SimpleTreeNode(label: "a")
    let large = SimpleTreeNode(label: "a", children: (0..<9).map { _ in SimpleTreeNode(label: "b") })
    // 9 insertions are unavoidable: bound = 1 - 9/10
    #expect(abs(fingerprint(of: small).tsedUpperBound(to: fingerprint(of: large)) - 0.1) < 1e-9)
}

// MARK: - Scanner reports TSED

@Test("Scanner reports the TSED score for every pair above the threshold")
func testScannerReportsTSED() async throws {
    let elements = sources.map { element($0.1, name: $0.0) }
    let threshold = 0.3
    let results = try await SimilarityScanner().findSimilarPairs(in: elements, threshold: threshold)
    
    let calculator = SimilarityCalculator()
    var expected: [String: Double] = [:]
    for i in 0..<elements.count {
        for j in (i + 1)..<elements.count {
            let score = calculator.calculateSimilarity(between: elements[i].treeNode, and: elements[j].treeNode).similarityScore
            if score >= threshold {
                expected[[elements[i].name, elements[j].name].sorted().joined(separator: "-")] = score
            }
        }
    }
    
    var actual: [String: Double] = [:]
    for (e1, e2, score) in results {
        actual[[e1.name, e2.name].sorted().joined(separator: "-")] = score
    }
    
    #expect(actual == expected)
    #expect(actual["add-sum"] == 1.0)
}
