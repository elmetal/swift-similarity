import Testing
@testable import swift_similarity

@Test("TreeNode creation")
func testTreeNodeCreation() {
    let node = SimpleTreeNode(label: "test", children: [])
    #expect(node.label == "test")
    #expect(node.children.isEmpty)
} 