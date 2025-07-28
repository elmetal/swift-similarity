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
        
        // FIXME: Handle "Syntax" nodes using SyntaxKind for better type resolution
        if typeName == "Syntax" {
            return createLabelFromSyntaxKind(node)
        }
        
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
            
        // MARK: - Literal Expressions (Priority 2)
        case let stringLiteral as StringLiteralExprSyntax:
            let segments = stringLiteral.segments.count
            let literalValue = stringLiteral.representedLiteralValue ?? ""
            let shortValue = literalValue.count > 10 ? String(literalValue.prefix(10)) + "..." : literalValue
            return "StringLiteral(\"\(shortValue)\",segments:\(segments))"
            
        case let boolLiteral as BooleanLiteralExprSyntax:
            let value = boolLiteral.literal.text
            return "BoolLiteral(\(value))"
            
        case let nilLiteral as NilLiteralExprSyntax:
            return "NilLiteral"
            
        case let floatLiteral as FloatLiteralExprSyntax:
            let value = floatLiteral.literal.text
            return "FloatLiteral(\(value))"
            
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
            
        // MARK: - Binary and Unary Operators (Priority 2)
        case let binaryExpr as BinaryOperatorExprSyntax:
            let operatorText = binaryExpr.operator.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "BinaryOp(\(operatorText))"
            
        case let prefixExpr as PrefixOperatorExprSyntax:
            let operatorText = prefixExpr.operator.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "PrefixOp(\(operatorText))"
            
        case let postfixExpr as PostfixOperatorExprSyntax:
            let operatorText = postfixExpr.operator.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "PostfixOp(\(operatorText))"
            
        case let ternaryExpr as TernaryExprSyntax:
            return "TernaryOp(?:)"
            
        case let subscriptExpr as SubscriptCallExprSyntax:
            let argCount = subscriptExpr.arguments.count
            return "Subscript(args:\(argCount))"
            
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
            
        // MARK: - Collection Expressions (Priority 2)
        case let arrayExpr as ArrayExprSyntax:
            let elementCount = arrayExpr.elements.count
            return "ArrayExpr(elements:\(elementCount))"
            
        case let dictExpr as DictionaryExprSyntax:
            let elementCount = dictExpr.content.as(DictionaryElementListSyntax.self)?.count ?? 0
            return "DictExpr(elements:\(elementCount))"
            
        case let tupleExpr as TupleExprSyntax:
            let elementCount = tupleExpr.elements.count
            return "TupleExpr(elements:\(elementCount))"
            
        case _ as InOutExprSyntax:
            return "InOutExpr"
            
        // MARK: - Type Expressions and Closures (Priority 2)  
        case let closureExpr as ClosureExprSyntax:
            let paramCount = closureExpr.signature?.parameterClause?.as(ClosureParameterClauseSyntax.self)?.parameters.count ?? 0
            let hasReturn = closureExpr.signature?.returnClause != nil
            return "ClosureExpr(params:\(paramCount),hasReturn:\(hasReturn))"
            
        case let optionalType as OptionalTypeSyntax:
            let wrappedType = optionalType.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return "OptionalType(\(wrappedType))"
            
        case let arrayType as ArrayTypeSyntax:
            let elementType = arrayType.element.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return "ArrayType([\(elementType)])"
            
        case let dictType as DictionaryTypeSyntax:
            let keyType = dictType.key.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let valueType = dictType.value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return "DictType([\(keyType):\(valueType)])"
            
        case let tupleType as TupleTypeSyntax:
            let elementCount = tupleType.elements.count
            return "TupleType(elements:\(elementCount))"
            
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
            
            // TODO: Handle generic "Syntax" nodes that lose type information
            // Many nodes return "Syntax" as typename, need deeper investigation
            
            // Avoid empty labels
            return cleanTypeName.isEmpty ? "Unknown" : cleanTypeName
        }
    }
    
    /// Creates a label from SyntaxKind for nodes that lose concrete type information
    /// - Parameter node: The syntax node with generic "Syntax" type
    /// - Returns: A descriptive label based on SyntaxKind
    private static func createLabelFromSyntaxKind(_ node: some SyntaxProtocol) -> String {
        let kind = node.kind
        
        switch kind {
        // Statements  
        case .expressionStmt: return "ExpressionStmt"
        case .returnStmt: return "ReturnStmt"
        case .continueStmt: return "ContinueStmt"
        case .breakStmt: return "BreakStmt"
        case .throwStmt: return "ThrowStmt"
        case .deferStmt: return "DeferStmt"
        case .ifExpr: return "IfExpr"
        case .guardStmt: return "GuardStmt"
        case .whileStmt: return "WhileStmt"
        case .forStmt: return "ForStmt"
        case .switchExpr: return "SwitchExpr"
        case .doStmt: return "DoStmt"
        
        // Expressions
        case .binaryOperatorExpr: return "BinaryOp"
        case .prefixOperatorExpr: return "PrefixOp" 
        case .postfixOperatorExpr: return "PostfixOp"
        case .memberAccessExpr: return "MemberAccess"
        case .subscriptCallExpr: return "SubscriptCall"
        case .functionCallExpr: return "FunctionCall"
        case .declReferenceExpr: return "DeclRef"
        case .stringLiteralExpr: return "StringLiteral"
        case .integerLiteralExpr: return "IntLiteral"
        case .floatLiteralExpr: return "FloatLiteral"
        case .booleanLiteralExpr: return "BoolLiteral"
        case .nilLiteralExpr: return "NilLiteral"
        case .arrayExpr: return "ArrayExpr"
        case .dictionaryExpr: return "DictExpr"
        case .tupleExpr: return "TupleExpr"
        case .closureExpr: return "ClosureExpr"
        case .assignmentExpr: return "Assignment"
        case .sequenceExpr: return "SequenceExpr"
        case .ternaryExpr: return "TernaryExpr"
        
        // Declarations
        case .functionDecl: return "FunctionDecl"
        case .variableDecl: return "VariableDecl"
        case .structDecl: return "StructDecl"
        case .classDecl: return "ClassDecl"
        case .enumDecl: return "EnumDecl"
        case .protocolDecl: return "ProtocolDecl"
        case .initializerDecl: return "InitDecl"
        case .deinitializerDecl: return "DeinitDecl"
        case .subscriptDecl: return "SubscriptDecl"
        case .operatorDecl: return "OperatorDecl"
        case .typeAliasDecl: return "TypeAliasDecl"
        case .associatedTypeDecl: return "AssociatedTypeDecl"
        
        // Types
        case .arrayType: return "ArrayType"
        case .dictionaryType: return "DictType"
        case .optionalType: return "OptionalType"
        case .implicitlyUnwrappedOptionalType: return "ImplicitUnwrappedOptional"
        case .tupleType: return "TupleType"
        case .functionType: return "FunctionType"
        case .identifierType: return "IdentifierType"
        case .classRestrictionType: return "ClassRestrictionType"
        
        // Patterns
        case .identifierPattern: return "IdentifierPattern"
        case .wildcardPattern: return "WildcardPattern"
        case .tuplePattern: return "TuplePattern"
        case .expressionPattern: return "ExpressionPattern"
        
        // Basic elements
        case .token: return "Token"
        case .codeBlockItem: return "CodeBlockItem"
        case .codeBlock: return "CodeBlock"
        case .functionParameterClause: return "ParameterClause"
        case .genericParameterClause: return "GenericParams"
        case .genericArgumentClause: return "GenericArgs"
        case .whereClause: return "WhereClause"
        case .conditionElement: return "ConditionElement"
        case .availabilityCondition: return "AvailabilityCondition"
        case .matchingPatternCondition: return "MatchingPatternCondition"
        case .optionalBindingCondition: return "OptionalBindingCondition"
        
        default:
            // For unhandled kinds, return the kind name
            return "Syntax(\(kind))"
        }
    }
}
 