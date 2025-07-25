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