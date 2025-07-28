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
            
        // MARK: - Control Flow Statements (Priority 1)
        case let whileStmt as WhileStmtSyntax:
            return "WhileStmt"
            
        case let guardStmt as GuardStmtSyntax:
            let conditionCount = guardStmt.conditions.count
            return "GuardStmt(conditions:\(conditionCount))"
            
        case let switchExpr as SwitchExprSyntax:
            let caseCount = switchExpr.cases.count
            return "SwitchExpr(cases:\(caseCount))"
            
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
            
        case let variableDecl as VariableDeclSyntax:
            let bindingCount = variableDecl.bindings.count
            let hasGetter = variableDecl.bindings.contains { $0.accessorBlock != nil }
            let modifiers = variableDecl.modifiers.map { $0.name.text }.joined(separator: ",")
            let isLet = variableDecl.bindingSpecifier.tokenKind == .keyword(.let)
            return "VariableDecl(bindings:\(bindingCount),computed:\(hasGetter),let:\(isLet),modifiers:\(modifiers))"
            
        case _ as ExpressionStmtSyntax:
            return "ExpressionStmt"
            
        case let assignmentExpr as AssignmentExprSyntax:
            return "Assignment"
            
        // MARK: - Basic Declaration Types (Priority 1)
        case let structDecl as StructDeclSyntax:
            let structName = structDecl.name.text
            let memberCount = structDecl.memberBlock.members.count
            let inheritanceInfo = structDecl.inheritanceClause?.inheritedTypes.map { $0.type.description }.joined(separator: ",") ?? ""
            return "StructDecl(\(structName),members:\(memberCount),inherits:\(inheritanceInfo))"
            
        case let classDecl as ClassDeclSyntax:
            let className = classDecl.name.text
            let memberCount = classDecl.memberBlock.members.count
            let inheritanceInfo = classDecl.inheritanceClause?.inheritedTypes.map { $0.type.description }.joined(separator: ",") ?? ""
            let modifiers = classDecl.modifiers.map { $0.name.text }.joined(separator: ",")
            return "ClassDecl(\(className),members:\(memberCount),inherits:\(inheritanceInfo),modifiers:\(modifiers))"
            
        case let enumDecl as EnumDeclSyntax:
            let enumName = enumDecl.name.text
            let caseCount = enumDecl.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }.count
            let inheritanceInfo = enumDecl.inheritanceClause?.inheritedTypes.map { $0.type.description }.joined(separator: ",") ?? ""
            return "EnumDecl(\(enumName),cases:\(caseCount),inherits:\(inheritanceInfo))"
            
        case let protocolDecl as ProtocolDeclSyntax:
            let protocolName = protocolDecl.name.text
            let requirementCount = protocolDecl.memberBlock.members.count
            let inheritanceInfo = protocolDecl.inheritanceClause?.inheritedTypes.map { $0.type.description }.joined(separator: ",") ?? ""
            return "ProtocolDecl(\(protocolName),requirements:\(requirementCount),inherits:\(inheritanceInfo))"
            
        case let initDecl as InitializerDeclSyntax:
            let paramCount = initDecl.signature.parameterClause.parameters.count
            let isOptional = initDecl.optionalMark != nil
            let modifiers = initDecl.modifiers.map { $0.name.text }.joined(separator: ",")
            return "InitDecl(params:\(paramCount),optional:\(isOptional),modifiers:\(modifiers))"
            
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
 