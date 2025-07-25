import Foundation

// MARK: - Tree Node Structure

/// A protocol representing a generic tree node structure.
public protocol TreeNode {
    /// The label identifying this node.
    var label: String { get }
    /// Child nodes of this node.
    var children: [TreeNode] { get }
}

/// A concrete implementation of TreeNode.
public struct SimpleTreeNode: TreeNode {
    public let label: String
    public let children: [TreeNode]
    
    /// Creates a new SimpleTreeNode with the specified label and children.
    /// - Parameters:
    ///   - label: The label for this node
    ///   - children: Child nodes (defaults to empty array)
    public init(label: String, children: [TreeNode] = []) {
        self.label = label
        self.children = children
    }
} 