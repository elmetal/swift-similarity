import SwiftSyntax

// MARK: - Conformance Index

/// Which protocols each type conforms to and what each protocol requires, collected from the
/// scanned files, so that `MemberSimilarityScanner` can leave out members that only satisfy a
/// protocol requirement (protocol witnesses).
///
/// Types conforming to the same protocol necessarily declare the same requirements, so comparing
/// those members would report the conformance rather than duplicated code.
///
/// Types and protocols are identified by their simple name: `Outer.Inner`, `Inner` and
/// `Inner<Int>` all refer to `Inner`. Conformances are combined from the type's declaration and
/// all of its extensions in the scanned files. Protocols declared outside the scanned files are
/// only known if they are in `standardLibraryRequirements`.
public struct ConformanceIndex: Sendable, Equatable {
    /// A protocol requirement, matched against members by kind, `static` and name. Types are not
    /// compared, because associated types and `Self` are written differently in the witness.
    public struct Requirement: Hashable, Sendable {
        public let kind: TypeMember.Kind
        public let isStatic: Bool
        public let name: String

        public init(kind: TypeMember.Kind, isStatic: Bool = false, name: String) {
            self.kind = kind
            self.isStatic = isStatic
            self.name = name
        }

        /// The requirement a member would satisfy.
        init(witness member: TypeMember) {
            var name = member.name
            // `init?(rawValue:)` and `init!(rawValue:)` satisfy `init(rawValue:)` and vice versa.
            if member.kind == .initializer {
                name = name.replacingOccurrences(of: "init?(", with: "init(").replacingOccurrences(of: "init!(", with: "init(")
            }
            self.init(kind: member.kind, isStatic: member.isStatic, name: name)
        }

        /// The requirement a protocol member declares. An associated type is satisfied by a
        /// typealias (or a nested type, which is not a member).
        init(requirement member: TypeMember) {
            let witness = Requirement(witness: member)
            self.init(kind: member.kind == .associatedType ? .typeAlias : witness.kind, isStatic: witness.isStatic, name: witness.name)
        }
    }

    /// Protocols each type (or protocol) inherits from, by simple type name.
    public private(set) var conformances: [String: Set<String>] = [:]
    /// Requirements declared by each protocol in the scanned files, by protocol name.
    public private(set) var requirements: [String: Set<Requirement>] = [:]

    public init() {}

    // MARK: Building

    /// Records the protocols that `declaration` adds to its type, and the requirements of a protocol.
    public mutating func add(_ declaration: some DeclGroupSyntax) {
        guard let typeName = Self.typeName(of: declaration) else { return }
        var inherited = Set(declaration.inheritanceClause?.inheritedTypes.flatMap { Self.protocolNames(in: $0.type) } ?? [])
        // An enum with a raw type (`enum Status: String`) is implicitly RawRepresentable.
        if declaration.is(EnumDeclSyntax.self), !inherited.isDisjoint(with: Self.rawValueTypes) {
            inherited.insert("RawRepresentable")
        }
        conformances[typeName, default: []].formUnion(inherited)
        if declaration.is(ProtocolDeclSyntax.self) {
            requirements[typeName, default: []].formUnion(TypeMember.members(of: declaration).map(Requirement.init(requirement:)))
        }
    }

    /// Adds everything `other` recorded.
    public mutating func merge(_ other: ConformanceIndex) {
        conformances.merge(other.conformances) { $0.union($1) }
        requirements.merge(other.requirements) { $0.union($1) }
    }

    // MARK: Queries

    /// Every requirement of every protocol the type named `typeName` conforms to, directly or
    /// through protocol inheritance. For a protocol (whose extensions provide default
    /// implementations), its own requirements are included.
    public func requirements(forTypeNamed typeName: String) -> Set<Requirement> {
        let name = Self.simpleName(typeName)
        var visited: Set<String> = []
        var pending = Array(conformances[name] ?? [])
        if requirements[name] != nil {
            pending.append(name)
        }
        var result: Set<Requirement> = []
        while let protocolName = pending.popLast() {
            guard visited.insert(protocolName).inserted else { continue }
            // A protocol declared in the scanned files wins over a standard library one of the same name.
            if let declared = requirements[protocolName] {
                result.formUnion(declared)
            } else if let known = Self.standardLibraryRequirements[protocolName] {
                result.formUnion(known)
            }
            pending.append(contentsOf: conformances[protocolName] ?? Self.standardLibraryInheritance[protocolName] ?? [])
        }
        return result
    }

    /// The requirements of the protocols declared in the scanned files that the type named
    /// `typeName` conforms to (directly or through protocol inheritance), each with the names of
    /// the protocols declaring it. For a protocol, its own requirements are included, so members of
    /// its extensions map to the requirements they provide default implementations for.
    ///
    /// Standard library protocols are left out: their requirements cannot get one default
    /// implementation shared by the scanned types.
    public func declaredRequirements(forTypeNamed typeName: String) -> [Requirement: Set<String>] {
        let name = Self.simpleName(typeName)
        var visited: Set<String> = []
        var pending = Array(conformances[name] ?? [])
        if requirements[name] != nil {
            pending.append(name)
        }
        var result: [Requirement: Set<String>] = [:]
        while let protocolName = pending.popLast() {
            guard visited.insert(protocolName).inserted else { continue }
            for requirement in requirements[protocolName] ?? [] {
                result[requirement, default: []].insert(protocolName)
            }
            pending.append(contentsOf: conformances[protocolName] ?? Self.standardLibraryInheritance[protocolName] ?? [])
        }
        return result
    }

    /// The members of `element` that do not satisfy a requirement of a protocol its type conforms
    /// to, or nil if it has no members. Protocols keep all their members, since their members are
    /// the requirements being compared.
    public func membersExcludingWitnesses(of element: CodeElement) -> [TypeMember]? {
        guard let members = element.members else { return nil }
        guard element.elementType != .protocol else { return members }
        let required = requirements(forTypeNamed: element.name)
        guard !required.isEmpty else { return members }
        return members.filter { !required.contains(Requirement(witness: $0)) }
    }

    // MARK: Names

    /// The simple name of the type a declaration declares or extends.
    static func typeName(of declaration: some DeclGroupSyntax) -> String? {
        let syntax = Syntax(declaration)
        if let decl = syntax.as(StructDeclSyntax.self) { return decl.name.text }
        if let decl = syntax.as(ClassDeclSyntax.self) { return decl.name.text }
        if let decl = syntax.as(EnumDeclSyntax.self) { return decl.name.text }
        if let decl = syntax.as(ActorDeclSyntax.self) { return decl.name.text }
        if let decl = syntax.as(ProtocolDeclSyntax.self) { return decl.name.text }
        if let decl = syntax.as(ExtensionDeclSyntax.self) { return simpleName(decl.extendedType.trimmedDescription) }
        return nil
    }

    /// `Outer.Inner<T>` → `Inner`; `[Int]` → `Array`; `Int?` → `Optional`.
    static func simpleName(_ typeText: String) -> String {
        var text = typeText.filter { !$0.isWhitespace }
        if text.hasSuffix("?") { return "Optional" }
        if text.hasPrefix("[") { return text.contains(":") ? "Dictionary" : "Array" }
        if let genericStart = text.firstIndex(of: "<") {
            text = String(text[..<genericStart])
        }
        return text.split(separator: ".").last.map(String.init) ?? text
    }

    /// Names in an inheritance clause entry: `P`, `Module.P`, `P & Q`, `@unchecked Sendable`.
    private static func protocolNames(in type: TypeSyntax) -> [String] {
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.flatMap { protocolNames(in: $0.type) }
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return protocolNames(in: attributed.baseType)
        }
        if type.is(SuppressedTypeSyntax.self) {
            // `~Copyable` removes a conformance instead of adding one.
            return []
        }
        return [simpleName(type.trimmedDescription)]
    }

    // MARK: Standard Library

    /// Requirements of common standard library protocols whose declarations are not scanned.
    public static let standardLibraryRequirements: [String: Set<Requirement>] = [
        "Equatable": [Requirement(kind: .method, isStatic: true, name: "==(_:_:)")],
        "Hashable": [Requirement(kind: .method, name: "hash(into:)"), Requirement(kind: .property, name: "hashValue")],
        "Comparable": [Requirement(kind: .method, isStatic: true, name: "<(_:_:)")],
        "Identifiable": [Requirement(kind: .property, name: "id"), Requirement(kind: .typeAlias, name: "ID")],
        "CustomStringConvertible": [Requirement(kind: .property, name: "description")],
        "CustomDebugStringConvertible": [Requirement(kind: .property, name: "debugDescription")],
        "LosslessStringConvertible": [Requirement(kind: .initializer, name: "init(_:)")],
        "Encodable": [Requirement(kind: .method, name: "encode(to:)")],
        "Decodable": [Requirement(kind: .initializer, name: "init(from:)")],
        "RawRepresentable": [
            Requirement(kind: .property, name: "rawValue"),
            Requirement(kind: .initializer, name: "init(rawValue:)"),
            Requirement(kind: .typeAlias, name: "RawValue"),
        ],
        "CaseIterable": [Requirement(kind: .property, isStatic: true, name: "allCases"), Requirement(kind: .typeAlias, name: "AllCases")],
        "Error": [],
        "LocalizedError": [
            Requirement(kind: .property, name: "errorDescription"),
            Requirement(kind: .property, name: "failureReason"),
            Requirement(kind: .property, name: "recoverySuggestion"),
            Requirement(kind: .property, name: "helpAnchor"),
        ],
        "Sequence": [Requirement(kind: .method, name: "makeIterator()"), Requirement(kind: .typeAlias, name: "Element"), Requirement(kind: .typeAlias, name: "Iterator")],
        "IteratorProtocol": [Requirement(kind: .method, name: "next()"), Requirement(kind: .typeAlias, name: "Element")],
        "Collection": [
            Requirement(kind: .property, name: "startIndex"),
            Requirement(kind: .property, name: "endIndex"),
            Requirement(kind: .method, name: "index(after:)"),
            Requirement(kind: .subscript, name: "subscript(_:)"),
            Requirement(kind: .typeAlias, name: "Index"),
        ],
        "BidirectionalCollection": [Requirement(kind: .method, name: "index(before:)")],
        "ExpressibleByStringLiteral": [Requirement(kind: .initializer, name: "init(stringLiteral:)")],
        "ExpressibleByIntegerLiteral": [Requirement(kind: .initializer, name: "init(integerLiteral:)")],
        "ExpressibleByArrayLiteral": [Requirement(kind: .initializer, name: "init(arrayLiteral:)")],
        "ExpressibleByDictionaryLiteral": [Requirement(kind: .initializer, name: "init(dictionaryLiteral:)")],
        "ExpressibleByBooleanLiteral": [Requirement(kind: .initializer, name: "init(booleanLiteral:)")],
        "ExpressibleByNilLiteral": [Requirement(kind: .initializer, name: "init(nilLiteral:)")],
    ]

    /// Types that give an enum raw values, making it RawRepresentable.
    static let rawValueTypes: Set<String> = [
        "String", "Character", "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float",
    ]

    /// Protocol inheritance among `standardLibraryRequirements`.
    public static let standardLibraryInheritance: [String: Set<String>] = [
        "Hashable": ["Equatable"],
        "Comparable": ["Equatable"],
        "Codable": ["Encodable", "Decodable"],
        "LocalizedError": ["Error"],
        "Collection": ["Sequence"],
        "BidirectionalCollection": ["Collection"],
        "RandomAccessCollection": ["BidirectionalCollection"],
        "MutableCollection": ["Collection"],
        "RangeReplaceableCollection": ["Collection"],
        "StringProtocol": ["BidirectionalCollection", "Comparable", "Hashable", "CustomStringConvertible"],
        "OptionSet": ["RawRepresentable"],
    ]
}
