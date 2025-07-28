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
        let label = createSemanticLabel(for: node)
        let children = node.children(viewMode: .sourceAccurate).map { convertSyntaxNode($0) }
        return SimpleTreeNode(label: label, children: children)
    }
    
    /// Creates a semantic label that captures both structure and content information.
    /// - Parameter node: The syntax node to create a label for
    /// - Returns: A descriptive label including type and semantic information
    private static func createSemanticLabel(for node: some SyntaxProtocol) -> String {
        let typeName = String(describing: type(of: node))
        
        // Add semantic information based on node type
        switch node {
        case let funcDecl as FunctionDeclSyntax:
            let funcName = funcDecl.name.text
            let paramCount = funcDecl.signature.parameterClause.parameters.count
            return "FunctionDecl(\(funcName),params:\(paramCount))"
            
        case let identifier as IdentifierPatternSyntax:
            return "Identifier(\(identifier.identifier.text))"
            
        case let token as TokenSyntax:
            let tokenKind = token.tokenKind
            switch tokenKind {
            case .keyword(let keyword):
                return "Keyword(\(keyword))"
            case .identifier(let name):
                return "Identifier(\(name))"
            case .integerLiteral(let value):
                return "IntLiteral(\(value))"
            default:
                return "Token(\(tokenKind))"
            }
            
        case let forStmt as ForStmtSyntax:
            return "ForStmt"
            
        case let ifExpr as IfExprSyntax:
            return "IfExpr"
            
        case let returnStmt as ReturnStmtSyntax:
            return "ReturnStmt"
            
        case let memberAccess as MemberAccessExprSyntax:
            let baseName = memberAccess.base?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let memberName = memberAccess.declName.baseName.text
            return "MemberAccess(\(baseName).\(memberName))"
            
        case let functionCall as FunctionCallExprSyntax:
            let funcName = functionCall.calledExpression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let argCount = functionCall.arguments.count
            return "FunctionCall(\(funcName),args:\(argCount))"
            
        case _ as CodeBlockSyntax:
            return "CodeBlock"
            
        case _ as FunctionParameterClauseSyntax:
            return "ParameterClause"
            
        case _ as PatternBindingSyntax:
            return "PatternBinding"
            
        case _ as VariableDeclSyntax:
            return "VariableDecl"
            
        case _ as ExpressionStmtSyntax:
            return "ExpressionStmt"
            
        case let assignmentExpr as AssignmentExprSyntax:
            return "Assignment"
            
        case let memberAccess as MemberAccessExprSyntax:
            let memberName = memberAccess.declName.baseName.text
            return "MemberAccess(\(memberName))"
            
        case let declRefExpr as DeclReferenceExprSyntax:
            let refName = declRefExpr.baseName.text
            return "DeclRef(\(refName))"
            
        case _ as TupleExprSyntax:
            return "TupleExpr"
            
        case _ as InOutExprSyntax:
            return "InOutExpr"
            
        case _ as FunctionTypeSyntax:
            return "FunctionType"
            
        case _ as GenericParameterClauseSyntax:
            return "GenericParams"
            
        case _ as AttributeListSyntax:
            return "AttributeList"
            
        default:
            // For nodes without specific semantic info, use the type name
            // Remove "Syntax" suffix for cleaner labels and handle empty results
            let cleanTypeName = if typeName.hasSuffix("Syntax") {
                String(typeName.dropLast(6))
            } else {
                typeName
            }
            
            // Avoid empty labels
            return cleanTypeName.isEmpty ? "Unknown" : cleanTypeName
        }
    }
}
 