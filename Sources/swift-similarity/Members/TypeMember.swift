import SwiftSyntax

// MARK: - Type Member

/// A member declared directly in a type, protocol or extension, reduced to what describes its
/// interface: its kind, its name and its type. Bodies and attributes are left out.
///
/// Members are compared by `MemberSimilarity` to find types with the same shape (such as two
/// DTOs with the same fields) even when their member order or method bodies differ.
public struct TypeMember: Hashable, Sendable, CustomStringConvertible {
    /// The kind of member.
    public enum Kind: String, Sendable {
        case property
        case method
        case initializer
        case `subscript`
        case enumCase
        case typeAlias
        case associatedType
    }

    public let kind: Kind
    /// Whether the member is declared `static` or `class`.
    public let isStatic: Bool
    /// The member's name. Methods and initializers include their argument labels, as in
    /// `update(with:)` or `init(id:name:)`.
    public let name: String
    /// The member's type, normalized: whitespace removed and `Optional<T>`, `Array<T>` and
    /// `Dictionary<K, V>` written as `T?`, `[T]` and `[K:V]`. For methods, initializers and
    /// subscripts it is the signature (`(Int,String)throws->Bool`), for enum cases the associated
    /// values, and for typealiases the aliased type. Empty when the source does not state it, such
    /// as a property with an inferred type.
    public let type: String

    public init(kind: Kind, isStatic: Bool = false, name: String, type: String) {
        self.kind = kind
        self.isStatic = isStatic
        self.name = name
        self.type = type
    }

    public var description: String {
        let prefix = isStatic ? "static \(kind.rawValue)" : kind.rawValue
        return type.isEmpty ? "\(prefix) \(name)" : "\(prefix) \(name): \(type)"
    }
}

// MARK: - Extraction

extension TypeMember {
    /// The members declared directly in `declaration`'s member block, in source order.
    ///
    /// Members inside `#if` blocks are included from every clause. Nested types and macro
    /// expansions are not members here (nested types are compared as declarations of their own).
    public static func members(of declaration: some DeclGroupSyntax) -> [TypeMember] {
        var members: [TypeMember] = []
        collect(declaration.memberBlock.members, into: &members)
        return members
    }

    private static func collect(_ items: MemberBlockItemListSyntax, into members: inout [TypeMember]) {
        for item in items {
            let decl = item.decl
            if let variable = decl.as(VariableDeclSyntax.self) {
                let isStatic = hasStaticModifier(variable.modifiers)
                for binding in variable.bindings {
                    // Tuple patterns (`let (a, b) = ...`) have no single name; skip them.
                    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    members.append(TypeMember(
                        kind: .property,
                        isStatic: isStatic,
                        name: pattern.identifier.text,
                        type: binding.typeAnnotation.map { normalizedType($0.type) } ?? ""
                    ))
                }
            } else if let function = decl.as(FunctionDeclSyntax.self) {
                let signature = function.signature
                members.append(TypeMember(
                    kind: .method,
                    isStatic: hasStaticModifier(function.modifiers),
                    name: function.name.text + argumentLabels(signature.parameterClause, unlabeledByDefault: isOperator(function.name)),
                    type: signatureType(
                        parameters: signature.parameterClause,
                        effects: signature.effectSpecifiers.map { effectText($0.asyncSpecifier, $0.throwsClause) } ?? "",
                        returnType: signature.returnClause?.type
                    )
                ))
            } else if let initializer = decl.as(InitializerDeclSyntax.self) {
                let signature = initializer.signature
                members.append(TypeMember(
                    kind: .initializer,
                    name: "init\(initializer.optionalMark?.text ?? "")" + argumentLabels(signature.parameterClause),
                    type: signatureType(
                        parameters: signature.parameterClause,
                        effects: signature.effectSpecifiers.map { effectText($0.asyncSpecifier, $0.throwsClause) } ?? "",
                        returnType: nil
                    )
                ))
            } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                members.append(TypeMember(
                    kind: .subscript,
                    isStatic: hasStaticModifier(subscriptDecl.modifiers),
                    name: "subscript" + argumentLabels(subscriptDecl.parameterClause, unlabeledByDefault: true),
                    type: signatureType(parameters: subscriptDecl.parameterClause, effects: "", returnType: subscriptDecl.returnClause.type)
                ))
            } else if let enumCase = decl.as(EnumCaseDeclSyntax.self) {
                for element in enumCase.elements {
                    let associatedValues = element.parameterClause.map { clause in
                        "(" + clause.parameters.map { normalizedType($0.type) }.joined(separator: ",") + ")"
                    }
                    members.append(TypeMember(kind: .enumCase, name: element.name.text, type: associatedValues ?? ""))
                }
            } else if let typeAlias = decl.as(TypeAliasDeclSyntax.self) {
                members.append(TypeMember(kind: .typeAlias, name: typeAlias.name.text, type: normalizedType(typeAlias.initializer.value)))
            } else if let associatedType = decl.as(AssociatedTypeDeclSyntax.self) {
                members.append(TypeMember(
                    kind: .associatedType,
                    name: associatedType.name.text,
                    type: associatedType.inheritanceClause.map { stripWhitespace($0.inheritedTypes.trimmedDescription) } ?? ""
                ))
            } else if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
                for clause in ifConfig.clauses {
                    if case .decls(let nested) = clause.elements {
                        collect(nested, into: &members)
                    }
                }
            }
        }
    }

    private static func hasStaticModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    /// `(label:_:)` for the parameters' argument labels, as in Swift's own member names.
    ///
    /// Parameters of subscripts and operators have no argument label unless they are written with
    /// two names (`unlabeledByDefault`), so `subscript(index: Int)` is `subscript(_:)`.
    private static func argumentLabels(_ parameters: FunctionParameterClauseSyntax, unlabeledByDefault: Bool = false) -> String {
        "(" + parameters.parameters.map { parameter in
            let label = unlabeledByDefault && parameter.secondName == nil ? "_" : parameter.firstName.text
            return "\(label):"
        }.joined() + ")"
    }

    private static func isOperator(_ name: TokenSyntax) -> Bool {
        switch name.tokenKind {
        case .binaryOperator, .prefixOperator, .postfixOperator: return true
        default: return false
        }
    }

    private static func effectText(_ asyncSpecifier: TokenSyntax?, _ throwsClause: ThrowsClauseSyntax?) -> String {
        (asyncSpecifier == nil ? "" : "async") + (throwsClause.map { stripWhitespace($0.trimmedDescription) } ?? "")
    }

    /// `(T1,T2)effects->R`, with a missing return type, `()` and `Void` all written as `Void`.
    private static func signatureType(parameters: FunctionParameterClauseSyntax, effects: String, returnType: TypeSyntax?) -> String {
        let parameterTypes = parameters.parameters.map { parameter in
            normalizedType(parameter.type) + (parameter.ellipsis == nil ? "" : "...")
        }
        var result = "(" + parameterTypes.joined(separator: ",") + ")" + effects
        if let returnType {
            let normalized = normalizedType(returnType)
            result += "->" + (normalized == "()" ? "Void" : normalized)
        } else {
            result += "->Void"
        }
        return result
    }

    /// The type's text without whitespace, with standard library sugar applied consistently.
    static func normalizedType(_ type: TypeSyntax) -> String {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return normalizedType(optional.wrappedType) + "?"
        }
        if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return normalizedType(implicitlyUnwrapped.wrappedType) + "!"
        }
        if let array = type.as(ArrayTypeSyntax.self) {
            return "[" + normalizedType(array.element) + "]"
        }
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            return "[" + normalizedType(dictionary.key) + ":" + normalizedType(dictionary.value) + "]"
        }
        if let identifier = type.as(IdentifierTypeSyntax.self), let clause = identifier.genericArgumentClause {
            let arguments = clause.arguments.map { argument -> String in
                if let argumentType = Syntax(argument.argument).as(TypeSyntax.self) {
                    return normalizedType(argumentType)
                }
                return stripWhitespace(argument.argument.trimmedDescription)
            }
            switch (identifier.name.text, arguments.count) {
            case ("Optional", 1): return arguments[0] + "?"
            case ("Array", 1): return "[" + arguments[0] + "]"
            case ("Dictionary", 2): return "[" + arguments[0] + ":" + arguments[1] + "]"
            default: return identifier.name.text + "<" + arguments.joined(separator: ",") + ">"
            }
        }
        return stripWhitespace(type.trimmedDescription)
    }

    private static func stripWhitespace(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }
}

// MARK: - Similarity

/// Similarity of two types by their members, ignoring member order and bodies.
public enum MemberSimilarity {
    /// The similarity (0.0-1.0) of two member lists:
    /// `(exact + 0.5 × partial) / max(|members1|, |members2|)`.
    ///
    /// - `exact` counts members that match in kind, `static`, name (ignoring case) and type.
    ///   Two members without a stated type match exactly when their names match.
    /// - Among the remaining members, `partial` counts those matching in kind and `static` and in
    ///   either the name or the stated type (whichever gives more matches), so a renamed field or a
    ///   changed type still counts half.
    ///
    /// Each member is matched at most once, so the result is 1.0 only when the members are the
    /// same up to order. Two empty lists have similarity 1.0.
    public static func similarity(_ members1: [TypeMember], _ members2: [TypeMember]) -> Double {
        let largest = max(members1.count, members2.count)
        guard largest > 0 else { return 1.0 }

        struct ExactKey: Hashable { let kind: TypeMember.Kind; let isStatic: Bool; let name: String; let type: String }
        struct PartialKey: Hashable { let kind: TypeMember.Kind; let isStatic: Bool; let value: String }

        var remaining1 = Counter<ExactKey>()
        for member in members1 {
            remaining1.add(ExactKey(kind: member.kind, isStatic: member.isStatic, name: member.name.lowercased(), type: member.type))
        }
        var remaining2 = Counter<ExactKey>()
        for member in members2 {
            remaining2.add(ExactKey(kind: member.kind, isStatic: member.isStatic, name: member.name.lowercased(), type: member.type))
        }
        let exact = remaining1.removeCommon(with: &remaining2)

        func partialMatches(_ value: (ExactKey) -> String?) -> Int {
            var counts1 = Counter<PartialKey>()
            for (key, count) in remaining1.counts {
                if let value = value(key) { counts1.add(PartialKey(kind: key.kind, isStatic: key.isStatic, value: value), count: count) }
            }
            var counts2 = Counter<PartialKey>()
            for (key, count) in remaining2.counts {
                if let value = value(key) { counts2.add(PartialKey(kind: key.kind, isStatic: key.isStatic, value: value), count: count) }
            }
            return counts1.removeCommon(with: &counts2)
        }
        // Unstated types are unknown, so they never match by type alone.
        let partial = max(partialMatches { $0.name }, partialMatches { $0.type.isEmpty ? nil : $0.type })

        return (Double(exact) + 0.5 * Double(partial)) / Double(largest)
    }

    /// The largest similarity two member lists of these sizes can have, `min / max`, used to skip
    /// pairs without comparing their members.
    public static func upperBound(count1: Int, count2: Int) -> Double {
        let largest = max(count1, count2)
        return largest > 0 ? Double(min(count1, count2)) / Double(largest) : 1.0
    }
}

/// A multiset.
private struct Counter<Key: Hashable> {
    var counts: [Key: Int] = [:]

    mutating func add(_ key: Key, count: Int = 1) {
        counts[key, default: 0] += count
    }

    /// Removes the common part of both multisets from both and returns its size.
    mutating func removeCommon(with other: inout Counter<Key>) -> Int {
        var common = 0
        for (key, count) in counts {
            guard let otherCount = other.counts[key] else { continue }
            let shared = min(count, otherCount)
            common += shared
            counts[key] = count - shared
            other.counts[key] = otherCount - shared
        }
        return common
    }
}
