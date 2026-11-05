import Testing
@testable import swift_similarity

private func node(_ label: String, _ children: TreeNode...) -> TreeNode {
    SimpleTreeNode(label: label, children: children)
}

@Test("Label interner assigns dense ids in first-seen order")
func testLabelInterner() {
    var labels = LabelInterner()
    #expect(labels.id(for: "a") == 0)
    #expect(labels.id(for: "b") == 1)
    #expect(labels.id(for: "a") == 0)
    #expect(labels.count == 2)
}

@Test("Prepared tree holds the label sequences and both postorder indexes")
func testPreparedTreeStructure() {
    // a(b(d, e), c)
    let tree = node("a", node("b", node("d"), node("e")), node("c"))
    var labels = LabelInterner()
    let prepared = PreparedTree(tree, labels: &labels)
    let a = labels.id(for: "a"), b = labels.id(for: "b"), c = labels.id(for: "c")
    let d = labels.id(for: "d"), e = labels.id(for: "e")
    #expect(labels.count == 5)

    #expect(prepared.nodeCount == 5)
    #expect(prepared.preorder == [a, b, d, e, c])
    #expect(prepared.postorder == [d, e, b, c, a])

    // Postorder d=1 e=2 b=3 c=4 a=5; leftmost leaves 1 2 1 4 1; keyroots e, c, a.
    #expect(prepared.indexed.labels == prepared.postorder)
    #expect(prepared.indexed.leftmost == [0, 1, 2, 1, 4, 1])
    #expect(prepared.indexed.keyroots == [2, 4, 5])
    #expect(prepared.indexed.keyrootCost == 1 + 1 + 5)

    // Mirror a(c, b(e, d)): postorder c=1 e=2 d=3 b=4 a=5, the reverse of the preorder.
    #expect(prepared.mirrored.labels == Array(prepared.preorder.reversed()))
    #expect(prepared.mirrored.leftmost == [0, 1, 2, 3, 2, 1])
    #expect(prepared.mirrored.keyroots == [3, 4, 5])
    #expect(prepared.mirrored.keyrootCost == 1 + 3 + 5)
}

/// Deterministic pseudo-random generator so failures are reproducible.
@Test("Trees prepared once give the same results as preparing every pair", arguments: [
    APTED.OperationCosts(),
    APTED.OperationCosts(insertion: 1.0, deletion: 1.0, substitution: 0.3),
    APTED.OperationCosts(insertion: 0.8, deletion: 2.0, substitution: 1.5),
])
func testPreparedTreesMatchPerPairPreparation(costs: APTED.OperationCosts) {
    var rng = SplitMix64(seed: 2024)
    // Labels differ per tree so the shared interner sees ids assigned in many different orders.
    let trees = (0..<40).map { index in
        randomTree(size: Int.random(in: 1...14, using: &rng), labels: ["a", "b", "c", "d\(index % 3)"], using: &rng)
    }
    var labels = LabelInterner()
    let prepared = trees.map { PreparedTree($0, labels: &labels) }
    let apted = APTED(costs: costs)
    let calculator = SimilarityCalculator(configuration: .init(aptedCosts: costs))

    for i in trees.indices {
        for j in trees.indices {
            #expect(apted.editDistance(between: prepared[i], and: prepared[j]) == apted.editDistance(between: trees[i], and: trees[j]))
            #expect(apted.lowerBound(between: prepared[i], and: prepared[j]) == apted.lowerBound(between: trees[i], and: trees[j]))
            #expect(
                apted.lowerBound(between: prepared[i], and: prepared[j], exceeding: 2)
                    == apted.lowerBound(between: trees[i], and: trees[j], exceeding: 2)
            )
            for threshold in [0.3, 0.6, 0.9] {
                #expect(
                    calculator.similarity(between: prepared[i], and: prepared[j], atLeast: threshold)
                        == calculator.similarity(between: trees[i], and: trees[j], atLeast: threshold)
                )
            }
        }
    }
}

// MARK: - Reference construction

/// Postorder labels, leftmost leaves and keyroots built by plain recursion, the textbook way.
private func referenceIndex(_ root: TreeNode, mirrored: Bool, labels: inout LabelInterner) -> (labels: [Int], leftmost: [Int], keyroots: [Int]) {
    var postorderLabels: [Int] = []
    var leftmost: [Int] = [0]
    func visit(_ node: TreeNode) -> Int {
        var first: Int?
        for child in mirrored ? node.children.reversed() : node.children {
            let childLeftmost = visit(child)
            if first == nil { first = childLeftmost }
        }
        postorderLabels.append(labels.id(for: node.label))
        let own = first ?? postorderLabels.count
        leftmost.append(own)
        return own
    }
    _ = visit(root)
    var keyroots: [Int] = []
    for i in 1..<leftmost.count where !((i + 1)..<leftmost.count).contains(where: { leftmost[$0] == leftmost[i] }) {
        keyroots.append(i)
    }
    return (postorderLabels, leftmost, keyroots)
}

@Test("Prepared tree indexes match a recursive construction on random trees")
func testPreparedTreeMatchesRecursiveConstruction() {
    var rng = SplitMix64(seed: 7)
    for _ in 0..<300 {
        let tree = randomTree(size: Int.random(in: 1...30, using: &rng), labels: ["a", "b", "c", "d"], using: &rng)
        var labels = LabelInterner()
        let prepared = PreparedTree(tree, labels: &labels)
        for (index, mirrored) in [(prepared.indexed, false), (prepared.mirrored, true)] {
            let reference = referenceIndex(tree, mirrored: mirrored, labels: &labels)
            #expect(index.labels == reference.labels)
            #expect(index.leftmost == reference.leftmost)
            #expect(index.keyroots == reference.keyroots)
            #expect(index.keyrootCost == reference.keyroots.reduce(0) { $0 + $1 - reference.leftmost[$1] + 1 })
        }
        #expect(prepared.nodeCount == prepared.preorder.count)
        #expect(prepared.preorder == Array(prepared.mirrored.labels.reversed()))
        #expect(prepared.histogram.map(\.count).reduce(0, +) == prepared.nodeCount)
    }
}

@Test("Interned histogram bound equals the fingerprint bound", arguments: [
    APTED.OperationCosts(),
    APTED.OperationCosts(insertion: 1.0, deletion: 1.0, substitution: 0.3),
    APTED.OperationCosts(insertion: 0.8, deletion: 2.0, substitution: 1.5),
])
func testHistogramBoundMatchesFingerprint(costs: APTED.OperationCosts) {
    var rng = SplitMix64(seed: 11)
    let trees = (0..<40).map { _ in
        randomTree(size: Int.random(in: 1...20, using: &rng), labels: ["a", "b", "c", "d", "e"], using: &rng)
    }
    var labels = LabelInterner()
    let prepared = trees.map { PreparedTree($0, labels: &labels) }
    let fingerprints = trees.map { $0.extractFingerprint() }
    for i in trees.indices {
        for j in trees.indices {
            #expect(prepared[i].treeEditDistanceLowerBound(to: prepared[j], costs: costs)
                == fingerprints[i].treeEditDistanceLowerBound(to: fingerprints[j], costs: costs))
            #expect(prepared[i].tsedUpperBound(to: prepared[j], costs: costs)
                == fingerprints[i].tsedUpperBound(to: fingerprints[j], costs: costs))
        }
    }
}

// MARK: - Lower bound with a limit

@Test("Lower bound with a limit is exact within the limit and above it otherwise", arguments: [
    APTED.OperationCosts(),
    APTED.OperationCosts(insertion: 1.0, deletion: 1.0, substitution: 0.3),
    APTED.OperationCosts(insertion: 2.0, deletion: 1.0, substitution: 3.0),
    APTED.OperationCosts(insertion: 0.8, deletion: 1.3, substitution: 0.0),
])
func testLimitedLowerBound(costs: APTED.OperationCosts) {
    var rng = SplitMix64(seed: 31)
    let apted = APTED(costs: costs)
    for _ in 0..<400 {
        let tree1 = randomTree(size: Int.random(in: 1...25, using: &rng), labels: ["a", "b", "c"], using: &rng)
        let tree2 = randomTree(size: Int.random(in: 1...25, using: &rng), labels: ["a", "b", "c"], using: &rng)
        let full = apted.lowerBound(between: tree1, and: tree2)
        let distance = apted.editDistance(between: tree1, and: tree2)
        for limit in [0.0, 0.5, 1.0, 2.0, 3.7, 6.0, 10.0, 40.0] {
            let bounded = apted.lowerBound(between: tree1, and: tree2, exceeding: limit)
            #expect(bounded <= distance + 1e-9)
            if full <= limit {
                #expect(bounded == full)
            } else {
                #expect(bounded > limit)
                #expect(bounded <= full + 1e-9)
            }
        }
    }
}

@Test("Bounds just above a rounded limit still rule the pair out")
func testLowerBoundNearRoundedLimit() {
    // (1 - 0.8) * 3760 rounds to 751.999..., yet a distance of 752 still gives
    // 1 - 752 / 3760 == 0.8 in floating point, so a pair at distance 752 reaches threshold 0.8.
    let nodes = 3760
    let limit = (1.0 - 0.8) * Double(nodes)
    #expect(limit < 752)
    #expect(1.0 - 752.0 / Double(nodes) >= 0.8)
    func tree(renamed: Int) -> TreeNode {
        SimpleTreeNode(label: "r", children: (0..<(nodes - 1)).map { SimpleTreeNode(label: $0 < renamed ? "b" : "a") })
    }
    let apted = APTED()
    // Within reach of the threshold: the bound is exact.
    #expect(apted.lowerBound(between: tree(renamed: 0), and: tree(renamed: 752), exceeding: limit) == 752)
    // Far from it: the bound may stop early, but must not report a value the threshold test
    // accepts (such as 752), or the calculator would run the full distance for nothing.
    let bound = apted.lowerBound(between: tree(renamed: 0), and: tree(renamed: 900), exceeding: limit)
    #expect(bound <= 900)
    #expect(1.0 - bound / Double(nodes) < 0.8)
}

@Test("Concurrent map keeps the order of the elements")
func testConcurrentMapOrder() {
    let values = Array(0..<10_000)
    #expect(values.concurrentMap { $0 * 2 } == values.map { $0 * 2 })
    #expect([Int]().concurrentMap { $0 }.isEmpty)
}
