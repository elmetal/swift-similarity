import SwiftSyntax
import Foundation

// MARK: - AST to Tree Converter

/// Converts SwiftSyntax AST to generic TreeNode structure.
///
/// Labels follow the convention of tree-sitter ASTs used by TSED (arXiv:2404.08817):
/// - Syntax nodes are labeled by their node type (e.g. `FunctionDecl`, `IfExpr`).
/// - Keyword, punctuation and operator tokens are labeled by their text (e.g. `func`, `{`, `+`).
/// - Identifier and literal tokens are labeled by their category (e.g. `Identifier`, `IntegerLiteral`),
///   so renamed variables or changed constants only differ structurally if the structure differs.
///
/// Empty syntax collections (such as an empty modifier list) are omitted because they carry no
/// source text and would only add noise nodes to the tree.
public class ASTToTreeConverter {

    /// Options controlling how labels are generated.
    public struct Options: Sendable {
        /// Include identifier names in identifier labels (e.g. `Identifier(count)`).
        /// When false (default), all identifiers share the label `Identifier`.
        public let includeIdentifierNames: Bool
        /// Include literal values in literal labels (e.g. `IntegerLiteral(42)`).
        /// When false (default), literals are labeled by their kind only.
        public let includeLiteralValues: Bool

        public init(includeIdentifierNames: Bool = false, includeLiteralValues: Bool = false) {
            self.includeIdentifierNames = includeIdentifierNames
            self.includeLiteralValues = includeLiteralValues
        }
    }

    /// Converts a SourceFileSyntax to TreeNode.
    /// - Parameters:
    ///   - sourceFile: The SourceFileSyntax to convert
    ///   - options: Label generation options
    /// - Returns: The converted TreeNode
    public static func convert(_ sourceFile: SourceFileSyntax, options: Options = Options()) -> TreeNode {
        return convertSyntaxNode(sourceFile, options: options)
    }

    /// Converts any SyntaxProtocol node to TreeNode.
    /// - Parameters:
    ///   - node: The syntax node to convert
    ///   - options: Label generation options
    /// - Returns: The converted TreeNode
    public static func convertSyntaxNode(_ node: some SyntaxProtocol, options: Options = Options()) -> TreeNode {
        return convert(Syntax(node), options: options)
    }

    // MARK: - Private

    private static func convert(_ node: Syntax, options: Options) -> TreeNode {
        let children = node.children(viewMode: .sourceAccurate).compactMap { child -> TreeNode? in
            if child.kind.isSyntaxCollection && child.children(viewMode: .sourceAccurate).isEmpty {
                return nil
            }
            return convert(child, options: options)
        }
        return SimpleTreeNode(label: label(for: node, options: options), children: children)
    }

    /// Creates the label of a node.
    static func label(for node: Syntax, options: Options) -> String {
        if let token = node.as(TokenSyntax.self) {
            return tokenLabel(token, options: options)
        }
        return nodeTypeName(node)
    }

    /// Node type name without the `Syntax` suffix, e.g. `FunctionDeclSyntax` -> `FunctionDecl`.
    private static func nodeTypeName(_ node: Syntax) -> String {
        let typeName = String(describing: node.kind.syntaxNodeType)
        return typeName.hasSuffix("Syntax") ? String(typeName.dropLast(6)) : typeName
    }

    private static func tokenLabel(_ token: TokenSyntax, options: Options) -> String {
        switch token.tokenKind {
        case .identifier(let name), .dollarIdentifier(let name):
            return options.includeIdentifierNames ? "Identifier(\(name))" : "Identifier"
        case .integerLiteral(let value):
            return options.includeLiteralValues ? "IntegerLiteral(\(value))" : "IntegerLiteral"
        case .floatLiteral(let value):
            return options.includeLiteralValues ? "FloatLiteral(\(value))" : "FloatLiteral"
        case .stringSegment(let value):
            return options.includeLiteralValues ? "StringSegment(\(value))" : "StringSegment"
        case .regexLiteralPattern(let value):
            return options.includeLiteralValues ? "RegexPattern(\(value))" : "RegexPattern"
        case .shebang:
            return "Shebang"
        case .endOfFile:
            return "EndOfFile"
        default:
            // Keywords, punctuation and operators: their text identifies their role.
            let text = token.text
            return text.isEmpty ? "Token" : text
        }
    }
}
