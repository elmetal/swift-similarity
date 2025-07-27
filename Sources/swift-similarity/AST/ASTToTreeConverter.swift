import SwiftSyntax
import Foundation

// MARK: - AST to Tree Converter

/// Converts SwiftSyntax AST to generic TreeNode structure.
public class ASTToTreeConverter {
    
    /// Converts a SourceFileSyntax to TreeNode.
    /// - Parameter sourceFile: The SourceFileSyntax to convert
    /// - Returns: The converted TreeNode
    public static func convert(_ sourceFile: SourceFileSyntax) -> TreeNode {
        return convertSyntaxNode(sourceFile)
    }
    
    /// Converts any SyntaxProtocol node to TreeNode.
    /// - Parameter node: The syntax node to convert
    /// - Returns: The converted TreeNode
    public static func convertSyntaxNode(_ node: some SyntaxProtocol) -> TreeNode {
        let label = String(describing: type(of: node))
        let children = node.children(viewMode: .sourceAccurate).map { convertSyntaxNode($0) }
        return SimpleTreeNode(label: label, children: children)
    }
}
 