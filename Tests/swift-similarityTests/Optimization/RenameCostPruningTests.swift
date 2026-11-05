import Testing
import Foundation
@testable import swift_similarity

// The engines skip pairs with two exact bounds before computing the tree edit distance:
// the label-histogram bound (`ASTNodeFingerprint.tsedUpperBound`) and the preorder/postorder
// sequence bound (`APTED.lowerBound`). These tests check that with a non-default rename cost the
// pruned engines still find exactly the pairs (and scores) that brute-force TSED finds.

// MARK: - Helpers

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

private let labels = ["a", "b", "c", "d", "e"]

private func randomTree(size: Int, rng: inout SeededGenerator) -> TreeNode {
    var remaining = size - 1
    var children: [TreeNode] = []
    while remaining > 0 {
        let childSize = Int.random(in: 1...remaining, using: &rng)
        children.append(randomTree(size: childSize, rng: &rng))
        remaining -= childSize
    }
    return SimpleTreeNode(label: labels.randomElement(using: &rng)!, children: children)
}

/// A copy of `tree` with some nodes relabeled, some leaves added and some leaves removed, so that
/// variants of one base tree land on both sides of the threshold.
private func mutate(_ tree: TreeNode, rate: Double, rng: inout SeededGenerator) -> TreeNode {
    var children: [TreeNode] = []
    for child in tree.children {
        if child.children.isEmpty && Double.random(in: 0..<1, using: &rng) < rate / 2 {
            continue
        }
        children.append(mutate(child, rate: rate, rng: &rng))
    }
    if Double.random(in: 0..<1, using: &rng) < rate / 2 {
        children.insert(SimpleTreeNode(label: labels.randomElement(using: &rng)!), at: Int.random(in: 0...children.count, using: &rng))
    }
    let label = Double.random(in: 0..<1, using: &rng) < rate ? labels.randomElement(using: &rng)! : tree.label
    return SimpleTreeNode(label: label, children: children)
}

private func makeElements(seed: UInt64) -> [CodeElement] {
    var rng = SeededGenerator(state: seed)
    var elements: [CodeElement] = []
    for base in 0..<6 {
        let tree = randomTree(size: Int.random(in: 8...20, using: &rng), rng: &rng)
        for variant in 0..<6 {
            let name = "b\(base)v\(variant)"
            elements.append(CodeElement(
                elementType: .function,
                name: name,
                signature: name,
                filePath: "/test/\(name).swift", // distinct files: no pair is nested
                startLine: 1,
                endLine: 1,
                codePreview: name,
                treeNode: variant == 0 ? tree : mutate(tree, rate: Double.random(in: 0.05...0.4, using: &rng), rng: &rng)
            ))
        }
    }
    return elements
}

private func key(_ e1: CodeElement, _ e2: CodeElement) -> String {
    [e1.name, e2.name].sorted().joined(separator: "-")
}

/// Every pair whose TSED (computed without any bound) reaches the threshold.
private func bruteForce(_ elements: [CodeElement], costs: APTED.OperationCosts, threshold: Double) -> [String: Double] {
    let calculator = SimilarityCalculator(configuration: .init(aptedCosts: costs))
    var result: [String: Double] = [:]
    for i in 0..<elements.count {
        for j in (i + 1)..<elements.count {
            let score = calculator.calculateSimilarity(between: elements[i].treeNode, and: elements[j].treeNode).similarityScore
            if score >= threshold {
                result[key(elements[i], elements[j])] = score
            }
        }
    }
    return result
}

private func scores(_ pairs: [(CodeElement, CodeElement, Double)]) -> [String: Double] {
    Dictionary(pairs.map { (key($0.0, $0.1), $0.2) }, uniquingKeysWith: { first, _ in first })
}

private func renameCosts(_ substitution: Double) -> APTED.OperationCosts {
    APTED.OperationCosts(insertion: 1.0, deletion: 1.0, substitution: substitution)
}

// MARK: - Tests

@Test("Pruned engines find the same pairs as brute-force TSED with a non-default rename cost", arguments: [
    (0.3, 0.8), (0.3, 0.87), (0.5, 0.7), (1.5, 0.6),
])
func testPruningIsExactWithRenameCost(renameCost: Double, threshold: Double) async throws {
    let costs = renameCosts(renameCost)
    for seed: UInt64 in [1, 2, 3] {
        let elements = makeElements(seed: seed)
        let expected = bruteForce(elements, costs: costs, threshold: threshold)

        let vectorized = try await VectorizedPrefilteringEngine(configuration: .init(optimizationLevel: .conservative, costs: costs))
            .findCandidates(elements: elements, threshold: threshold)
        #expect(scores(vectorized) == expected, "vectorized, seed \(seed)")

        let (hierarchical, _) = try await HierarchicalProcessor(
            configuration: .optimal(for: .small, costs: costs),
            vectorizedConfig: nil,
            progressCallback: nil
        ).process(elements: elements, threshold: threshold)
        #expect(scores(hierarchical) == expected, "hierarchical, seed \(seed)")

        // The bounded calculator agrees with the unbounded one on every pair.
        let calculator = SimilarityCalculator(configuration: .init(aptedCosts: costs))
        var bounded: [String: Double] = [:]
        for i in 0..<elements.count {
            for j in (i + 1)..<elements.count {
                if let score = calculator.similarity(between: elements[i].treeNode, and: elements[j].treeNode, atLeast: threshold) {
                    bounded[key(elements[i], elements[j])] = score
                }
            }
        }
        #expect(bounded == expected, "calculator, seed \(seed)")
    }
}

@Test("The rename cost changes which pairs are found")
func testRenameCostChangesResults() async throws {
    let elements = makeElements(seed: 1)
    let unit = bruteForce(elements, costs: renameCosts(1.0), threshold: 0.8)
    let cheap = bruteForce(elements, costs: renameCosts(0.3), threshold: 0.8)
    // Cheaper renames never lower a score, and the generated variants include relabeled nodes.
    #expect(Set(unit.keys).isSubset(of: Set(cheap.keys)))
    #expect(cheap.count > unit.count)

    // The engines use the configured cost, not the default one.
    let found = try await VectorizedPrefilteringEngine(configuration: .init(optimizationLevel: .conservative, costs: renameCosts(0.3)))
        .findCandidates(elements: elements, threshold: 0.8)
    #expect(scores(found) == cheap)
}

@Test("Bounds stay below the TSED score with cheap renames", arguments: [0.0, 0.3, 0.5])
func testBoundsAreSoundWithRenameCost(renameCost: Double) {
    let costs = renameCosts(renameCost)
    let apted = APTED(costs: costs)
    let calculator = SimilarityCalculator(configuration: .init(aptedCosts: costs))
    let elements = makeElements(seed: 4)
    for i in 0..<elements.count {
        for j in (i + 1)..<elements.count {
            let tree1 = elements[i].treeNode
            let tree2 = elements[j].treeNode
            let distance = apted.editDistance(between: tree1, and: tree2)
            #expect(apted.lowerBound(between: tree1, and: tree2) <= distance + 1e-9)
            #expect(tree1.extractFingerprint().treeEditDistanceLowerBound(to: tree2.extractFingerprint(), costs: costs) <= distance + 1e-9)
            let score = calculator.calculateSimilarity(between: tree1, and: tree2).similarityScore
            #expect(tree1.extractFingerprint().tsedUpperBound(to: tree2.extractFingerprint(), costs: costs) >= score - 1e-9)
        }
    }
}
