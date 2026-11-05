import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import swift_similarity

/// The members of the first type, protocol or extension in `source`.
private func members(_ source: String) throws -> [TypeMember] {
    let file = Parser.parse(source: source)
    let group = try #require(file.statements.lazy.compactMap { $0.item.asProtocol(DeclGroupSyntax.self) }.first)
    return TypeMember.members(of: group)
}

private func extract(_ source: String) throws -> [CodeElement] {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("TypeMembers-\(UUID().uuidString).swift")
    try source.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    return try CodeElementExtractor(configuration: .init(minLines: 0)).extractElements(from: url.path)
}

// MARK: - Extraction

@Test("Extracts every kind of member with its name and normalized type")
func testMemberExtraction() throws {
    let found = try members("""
        struct Sample {
            let id: Int
            var a, b: String
            static var shared = Sample()
            var computed: Optional<Array<Int>> { nil }
            let (x, y) = (1, 2)
            init?(id: Int, _ name: String) throws {}
            func update(with value: Dictionary<String, Int>, _ flag: Bool) async throws -> [String: Int]? { nil }
            static func make() -> Void {}
            subscript(index: Int) -> String { "" }
            typealias Map = [String: Int]
            struct Nested { let value: Int }
            #if DEBUG
            func debugOnly() {}
            #endif
        }
        """)
    #expect(found.map(\.description) == [
        "property id: Int",
        "property a",
        "property b: String",
        "static property shared",
        "property computed: [Int]?",
        "initializer init?(id:_:): (Int,String)throws->Void",
        "method update(with:_:): ([String:Int],Bool)asyncthrows->[String:Int]?",
        "static method make(): ()->Void",
        "subscript subscript(index:): (Int)->String",
        "typeAlias Map: [String:Int]",
        "method debugOnly(): ()->Void",
    ])
}

@Test("Extracts enum cases, protocol requirements and associated types")
func testEnumAndProtocolMembers() throws {
    let cases = try members("""
        enum Event {
            case started, stopped(reason: String, code: Int)
            case progress(Double)
        }
        """)
    #expect(cases.map(\.description) == [
        "enumCase started",
        "enumCase stopped: (String,Int)",
        "enumCase progress: (Double)",
    ])

    let requirements = try members("""
        protocol Store {
            associatedtype Item: Hashable
            var items: [Item] { get }
            func insert(_ item: Item) -> Bool
        }
        """)
    #expect(requirements.map(\.description) == [
        "associatedType Item: Hashable",
        "property items: [Item]",
        "method insert(_:): (Item)->Bool",
    ])
}

@Test("The extractor records members of types but not of functions")
func testCodeElementMembers() throws {
    let elements = try extract("""
        struct Point {
            var x: Double
            var y: Double
            func length() -> Double { 0 }
        }
        """)
    let point = try #require(elements.first { $0.name == "Point" })
    #expect(point.members?.count == 3)
    let length = try #require(elements.first { $0.name == "length" })
    #expect(length.members == nil)
}

// MARK: - Similarity

private func property(_ name: String, _ type: String) -> TypeMember {
    TypeMember(kind: .property, name: name, type: type)
}

@Test("Identical members in any order score 1, disjoint members score 0")
func testSimilarityExtremes() {
    let members = [property("id", "Int"), property("name", "String"), property("email", "String?")]
    #expect(MemberSimilarity.similarity(members, members.reversed()) == 1.0)
    #expect(MemberSimilarity.similarity([], []) == 1.0)
    #expect(MemberSimilarity.similarity(members, [TypeMember(kind: .method, name: "run()", type: "()->Void")]) == 0.0)
}

@Test("Renamed fields or changed types count half, normalized by the larger type")
func testPartialMatches() {
    let user = [property("id", "Int"), property("name", "String"), property("email", "String")]
    // Same names and types, but `Name` differs only in case: still exact.
    #expect(MemberSimilarity.similarity(user, [property("ID", "Int"), property("Name", "String"), property("email", "String")]) == 1.0)
    // One field renamed (same type): 2 exact + 0.5.
    #expect(MemberSimilarity.similarity(user, [property("id", "Int"), property("name", "String"), property("mail", "String")]) == 2.5 / 3)
    // One type changed (same name): 2 exact + 0.5.
    #expect(MemberSimilarity.similarity(user, [property("id", "UUID"), property("name", "String"), property("email", "String")]) == 2.5 / 3)
    // An extra member lowers the score: 3 exact out of 4.
    #expect(MemberSimilarity.similarity(user, user + [property("age", "Int")]) == 0.75)
    // Each member matches once: two `String` fields cannot both match one.
    #expect(MemberSimilarity.similarity([property("a", "String"), property("b", "String")], [property("c", "String")]) == 0.25)
}

@Test("Kind and static must match, and unstated types never match by type alone")
func testKindStaticAndUnstatedTypes() {
    let instance = [property("count", "Int")]
    #expect(MemberSimilarity.similarity(instance, [TypeMember(kind: .property, isStatic: true, name: "count", type: "Int")]) == 0.0)
    #expect(MemberSimilarity.similarity(instance, [TypeMember(kind: .enumCase, name: "count", type: "Int")]) == 0.0)
    // Inferred types: same name matches exactly, different names do not match.
    #expect(MemberSimilarity.similarity([property("count", "")], [property("count", "")]) == 1.0)
    #expect(MemberSimilarity.similarity([property("count", "")], [property("total", "")]) == 0.0)
}

@Test("The upper bound from member counts is never below the similarity")
func testMemberCountUpperBound() {
    let small = [property("id", "Int"), property("name", "String")]
    let large = small + [property("age", "Int"), property("email", "String")]
    #expect(MemberSimilarity.upperBound(count1: 2, count2: 4) == 0.5)
    #expect(MemberSimilarity.similarity(small, large) <= MemberSimilarity.upperBound(count1: small.count, count2: large.count))
}

// MARK: - Scanner

@Test("The member scanner compares types within groups and skips nested and tiny types")
func testMemberScanner() throws {
    let elements = try extract("""
        struct User {
            let id: Int
            let name: String
            let email: String
        }
        class Account {
            var email: String
            var name: String
            var id: Int
            init() { email = ""; name = ""; id = 0 }
        }
        protocol UserLike {
            var id: Int { get }
            var name: String { get }
            var email: String { get }
        }
        protocol Named {
            var id: Int { get }
            var name: String { get }
            var email: String { get }
        }
        struct Outer {
            let id: Int
            let name: String
            struct Inner {
                let id: Int
                let name: String
            }
        }
        struct Tiny { let id: Int }
        struct AlsoTiny { let id: Int }
        func helper() {}
        """)
    let result = MemberSimilarityScanner().scan(elements, threshold: 0.6)
    let pairs = result.pairs.map { "\($0.first.name)/\($0.second.name)" }

    // User/Account: 3 exact members out of 4 (Account has an initializer).
    #expect(pairs.contains("User/Account"))
    #expect(result.pairs.first { $0.first.name == "User" && $0.second.name == "Account" }?.similarity == 0.75)
    // Protocols are compared with protocols, not with the types that look like them.
    #expect(pairs.contains("UserLike/Named"))
    #expect(!pairs.contains { $0.contains("UserLike/") && !$0.hasSuffix("Named") })
    // Outer and Inner are nested; Tiny types have fewer than two members.
    #expect(!pairs.contains("Outer/Inner"))
    #expect(!pairs.contains("Tiny/AlsoTiny"))
    // Inner and User share two members: 2 / 3 ≥ 0.6.
    #expect(pairs.contains("User/Inner"))

    // Most similar first, then in input order.
    #expect(result.pairs.map(\.similarity) == result.pairs.map(\.similarity).sorted(by: >))
    let stats = result.statistics
    #expect(stats.totalPairs == stats.nestedPairs + stats.pairsRuledOutByUpperBound + stats.pairsCompared)
    #expect(stats.similarPairs == result.pairs.count)
}
