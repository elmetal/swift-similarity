import Testing
@testable import swift_similarity

@Test("APTED operation costs creation")
func testOperationCosts() {
    let defaultCosts = APTED.OperationCosts()
    #expect(defaultCosts.insertion == 1.0)
    #expect(defaultCosts.deletion == 1.0)
    #expect(defaultCosts.substitution == 1.0)
    
    let customCosts = APTED.OperationCosts(insertion: 2.0, deletion: 3.0, substitution: 1.5)
    #expect(customCosts.insertion == 2.0)
    #expect(customCosts.deletion == 3.0)
    #expect(customCosts.substitution == 1.5)
}

@Test("APTED identical trees distance")
func testIdenticalTreesDistance() {
    let tree1 = SimpleTreeNode(label: "A", children: [
        SimpleTreeNode(label: "B"),
        SimpleTreeNode(label: "C")
    ])
    
    let tree2 = SimpleTreeNode(label: "A", children: [
        SimpleTreeNode(label: "B"),
        SimpleTreeNode(label: "C")
    ])
    
    let apted = APTED()
    let distance = apted.editDistance(between: tree1, and: tree2)
    #expect(distance == 0.0)
}

@Test("APTED single node trees distance")
func testSingleNodeTreesDistance() {
    let tree1 = SimpleTreeNode(label: "A")
    let tree2 = SimpleTreeNode(label: "B")
    
    let apted = APTED()
    let distance = apted.editDistance(between: tree1, and: tree2)
    #expect(distance == 1.0) // One substitution
}

@Test("APTED empty vs single node distance")
func testEmptyVsSingleNodeDistance() {
    let tree1 = SimpleTreeNode(label: "Root", children: [])
    let tree2 = SimpleTreeNode(label: "Root", children: [
        SimpleTreeNode(label: "Child")
    ])
    
    let apted = APTED()
    let distance = apted.editDistance(between: tree1, and: tree2)
    #expect(distance == 1.0) // One insertion
}

@Test("APTED custom costs")
func testCustomCosts() {
    let tree1 = SimpleTreeNode(label: "A")
    let tree2 = SimpleTreeNode(label: "B")
    
    let customCosts = APTED.OperationCosts(insertion: 2.0, deletion: 2.0, substitution: 3.0)
    let apted = APTED(costs: customCosts)
    let distance = apted.editDistance(between: tree1, and: tree2)
    #expect(distance == 3.0) // One substitution with cost 3.0
} 
// MARK: - Known tree edit distances

private func node(_ label: String, _ children: TreeNode...) -> TreeNode {
    SimpleTreeNode(label: label, children: children)
}

@Test("Zhang-Shasha paper example has distance 2")
func testZhangShashaPaperExample() {
    // f(d(a, c(b)), e) -> f(c(d(a, b)), e)
    let tree1 = node("f", node("d", node("a"), node("c", node("b"))), node("e"))
    let tree2 = node("f", node("c", node("d", node("a"), node("b"))), node("e"))
    
    let apted = APTED()
    #expect(apted.editDistance(between: tree1, and: tree2) == 2.0)
    #expect(apted.editDistance(between: tree2, and: tree1) == 2.0)
}

@Test("Trees with identical postorder label sequences are not identical")
func testSamePostorderDifferentStructure() {
    // Both have postorder sequence c, b, a; a sequence edit distance would return 0.
    let chain = node("a", node("b", node("c")))
    let siblings = node("a", node("c"), node("b"))
    
    let apted = APTED()
    #expect(apted.editDistance(between: chain, and: siblings) == 2.0)
}

@Test("Moving children uses the cheapest mapping")
func testSubtreeMove() {
    // r(x(p, q), y) -> r(x, y(p, q)):
    // rename x->y (keeps p, q), delete old y, insert new x = 3 (cheaper than moving p, q = 4).
    let tree1 = node("r", node("x", node("p"), node("q")), node("y"))
    let tree2 = node("r", node("x"), node("y", node("p"), node("q")))
    
    let apted = APTED()
    #expect(apted.editDistance(between: tree1, and: tree2) == 3.0)
}

@Test("Deleting an inner node keeps its children")
func testInnerNodeDeletion() {
    // a(b(c, d)) -> a(c, d): delete b only.
    let tree1 = node("a", node("b", node("c"), node("d")))
    let tree2 = node("a", node("c"), node("d"))
    
    let apted = APTED()
    #expect(apted.editDistance(between: tree1, and: tree2) == 1.0)
}

@Test("Asymmetric insertion and deletion costs")
func testAsymmetricCosts() {
    let small = node("Root")
    let large = node("Root", node("Child"), node("Child"))
    
    // TSED's tuned weights: insertion 0.8, deletion 1.0
    let apted = APTED(costs: APTED.OperationCosts(insertion: 0.8, deletion: 1.0, substitution: 1.0))
    #expect(abs(apted.editDistance(between: small, and: large) - 1.6) < 1e-9)
    #expect(apted.editDistance(between: large, and: small) == 2.0)
}

@Test("Rename is replaced by delete+insert when cheaper")
func testRenameVersusDeleteInsert() {
    let tree1 = node("A")
    let tree2 = node("B")
    
    let apted = APTED(costs: APTED.OperationCosts(insertion: 1.0, deletion: 1.0, substitution: 5.0))
    // Delete A + insert B (cost 2) is cheaper than renaming A to B (cost 5).
    #expect(apted.editDistance(between: tree1, and: tree2) == 2.0)
}

@Test("Distance is bounded by deleting and inserting everything")
func testUpperBound() {
    let tree1 = node("a", node("b"), node("c", node("d")))
    let tree2 = node("x", node("y", node("z")))
    
    let apted = APTED()
    let distance = apted.editDistance(between: tree1, and: tree2)
    // All labels differ: rename a->x, c->y, d->z and delete b = 4
    #expect(distance == 4.0)
}

// MARK: - Cross-check against the recursive forest distance definition

/// Naive memoized forest edit distance (Tai / Zhang-Shasha recurrence on rightmost roots).
private struct ReferenceTreeEditDistance {
    let costs: APTED.OperationCosts
    var memo: [String: Double] = [:]
    
    init(costs: APTED.OperationCosts) { self.costs = costs }
    
    private static func key(_ forest: [TreeNode]) -> String {
        forest.map { serialize($0) }.joined(separator: ",")
    }
    
    private static func serialize(_ tree: TreeNode) -> String {
        tree.label + "(" + tree.children.map { serialize($0) }.joined(separator: ",") + ")"
    }
    
    private static func size(_ forest: [TreeNode]) -> Int {
        forest.reduce(0) { $0 + 1 + size($1.children) }
    }
    
    mutating func distance(_ f: [TreeNode], _ g: [TreeNode]) -> Double {
        if f.isEmpty { return Double(Self.size(g)) * costs.insertion }
        if g.isEmpty { return Double(Self.size(f)) * costs.deletion }
        let memoKey = Self.key(f) + "|" + Self.key(g)
        if let cached = memo[memoKey] { return cached }
        
        let v = f.last!
        let w = g.last!
        let fRest = Array(f.dropLast())
        let gRest = Array(g.dropLast())
        
        let delete = distance(fRest + v.children, g) + costs.deletion
        let insert = distance(f, gRest + w.children) + costs.insertion
        let rename = distance(v.children, w.children) + distance(fRest, gRest)
            + (v.label == w.label ? 0 : costs.substitution)
        let result = min(delete, insert, rename)
        memo[memoKey] = result
        return result
    }
}

/// Deterministic pseudo-random generator so failures are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

private func randomTree(size: Int, labels: [String], rng: inout SplitMix64) -> TreeNode {
    let label = labels.randomElement(using: &rng)!
    var remaining = size - 1
    var children: [TreeNode] = []
    while remaining > 0 {
        let childSize = Int.random(in: 1...remaining, using: &rng)
        children.append(randomTree(size: childSize, labels: labels, rng: &rng))
        remaining -= childSize
    }
    return SimpleTreeNode(label: label, children: children)
}

@Test("Matches the recursive definition on random trees", arguments: [
    APTED.OperationCosts(),
    APTED.OperationCosts(insertion: 0.8, deletion: 1.0, substitution: 1.0),
    APTED.OperationCosts(insertion: 1.0, deletion: 2.0, substitution: 1.5),
])
func testMatchesReferenceImplementation(costs: APTED.OperationCosts) {
    var rng = SplitMix64(state: 42)
    let labels = ["a", "b", "c"]
    let apted = APTED(costs: costs)
    
    for _ in 0..<200 {
        let tree1 = randomTree(size: Int.random(in: 1...7, using: &rng), labels: labels, rng: &rng)
        let tree2 = randomTree(size: Int.random(in: 1...7, using: &rng), labels: labels, rng: &rng)
        var reference = ReferenceTreeEditDistance(costs: costs)
        let expected = reference.distance([tree1], [tree2])
        let actual = apted.editDistance(between: tree1, and: tree2)
        #expect(abs(actual - expected) < 1e-9)
    }
}
