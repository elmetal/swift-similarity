import Testing
import Foundation
@testable import swift_similarity

/// Extracts every declaration in `source` with its conformance index.
private func extract(_ source: String) throws -> (elements: [CodeElement], conformances: ConformanceIndex) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ConformanceIndex-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try source.write(to: directory.appendingPathComponent("Source.swift"), atomically: true, encoding: .utf8)
    let extraction = try CodeElementExtractor(configuration: .init(minLines: 0)).extract(fromPaths: [directory.path])
    return (extraction.elements, extraction.conformances)
}

private func names(_ members: [TypeMember]?) -> [String] {
    (members ?? []).map(\.name)
}

@Test("Witnesses of scanned protocols, inherited protocols and standard library protocols are left out")
func testWitnessExclusion() throws {
    let (elements, index) = try extract("""
        protocol Scope {
            var names: [String] { get }
            func lookup(_ name: String) -> Int?
        }
        protocol SequentialScope: Scope {
            associatedtype Item
            static var kind: String { get }
        }
        struct Block: SequentialScope, Equatable, CustomStringConvertible {
            typealias Item = Int
            static var kind: String { "block" }
            var names: [String]
            var statements: [String]
            func lookup(_ name: String) -> Int? { nil }
            func render() -> String { "" }
            static func == (lhs: Block, rhs: Block) -> Bool { true }
            var description: String { "" }
        }
        """)
    let block = try #require(elements.first { $0.name == "Block" })
    #expect(names(index.membersExcludingWitnesses(of: block)) == ["statements", "render()"])

    // Protocols keep their members: they are the requirements being compared.
    let scope = try #require(elements.first { $0.name == "Scope" })
    #expect(names(index.membersExcludingWitnesses(of: scope)) == ["names", "lookup(_:)"])
}

@Test("Conformances declared elsewhere apply to every declaration of the type, and protocol extensions lose their defaults")
func testConformanceAcrossDeclarations() throws {
    let (elements, index) = try extract("""
        protocol Shape {
            func area() -> Double
            func perimeter() -> Double
        }
        struct Square { var side: Double }
        extension Square: Shape {}
        extension Square {
            func area() -> Double { side * side }
            func perimeter() -> Double { 4 * side }
            func diagonal() -> Double { side * 2.squareRoot() }
        }
        extension Shape {
            func perimeter() -> Double { 0 }
            func describe() -> String { "" }
        }
        enum Status: String, Codable, CaseIterable {
            case on, off
            init?(rawValue: String) { nil }
            var rawValue: String { "" }
        }
        """)
    let squareMembers = elements.filter { $0.name == "Square" && $0.elementType == .extension }
        .map { names(index.membersExcludingWitnesses(of: $0)) }
    #expect(squareMembers.contains(["diagonal()"]))

    let shapeExtension = try #require(elements.first { $0.name == "Shape" && $0.elementType == .extension })
    #expect(names(index.membersExcludingWitnesses(of: shapeExtension)) == ["describe()"])

    // `init?(rawValue:)` satisfies `init(rawValue:)`; enum cases are never witnesses here.
    let status = try #require(elements.first { $0.name == "Status" })
    #expect(names(index.membersExcludingWitnesses(of: status)) == ["on", "off"])
}

@Test("Operators and subscripts use Swift's argument labels")
func testOperatorAndSubscriptNames() throws {
    let (elements, _) = try extract("""
        struct Vector {
            static func + (lhs: Vector, rhs: Vector) -> Vector { lhs }
            subscript(index: Int) -> Double { 0 }
            subscript(row r: Int, column c: Int) -> Double { 0 }
        }
        """)
    let vector = try #require(elements.first { $0.name == "Vector" })
    #expect(names(vector.members) == ["+(_:_:)", "subscript(_:)", "subscript(row:column:)"])
}

@Test("Simple names ignore modules, outer types and generic arguments")
func testSimpleNames() {
    #expect(ConformanceIndex.simpleName("Swift.Equatable") == "Equatable")
    #expect(ConformanceIndex.simpleName("Outer.Inner<Int>") == "Inner")
    #expect(ConformanceIndex.simpleName("[Int]") == "Array")
    #expect(ConformanceIndex.simpleName("[String: Int]") == "Dictionary")
    #expect(ConformanceIndex.simpleName("Int?") == "Optional")
}

@Test("Extensions that only implement the same protocol are no longer reported")
func testScannerSkipsConformanceOnlyExtensions() throws {
    let (elements, index) = try extract("""
        protocol Scope {
            var names: [String] { get }
            func lookup(_ name: String) -> Int?
            func parentScope() -> Int?
        }
        struct A {}
        struct B {}
        struct C {}
        extension A: Scope {
            var names: [String] { [] }
            func lookup(_ name: String) -> Int? { 1 }
            func parentScope() -> Int? { nil }
        }
        extension B: Scope {
            var names: [String] { ["b"] }
            func lookup(_ name: String) -> Int? { 2 }
            func parentScope() -> Int? { nil }
        }
        extension C: Scope {
            var names: [String] { [] }
            func lookup(_ name: String) -> Int? { 1 }
            func parentScope() -> Int? { nil }
            func extraOne() {}
            func extraTwo() {}
        }
        extension A {
            func extraOne() {}
            func extraTwo() {}
        }
        """)
    let scanner = MemberSimilarityScanner()
    let without = scanner.scan(elements, threshold: 0.8).pairs.map { "\($0.first.name)/\($0.second.name)" }
    #expect(without.contains("A/B"))

    let with = scanner.scan(elements, threshold: 0.8, conformances: index).pairs.map { "\($0.first.name)/\($0.second.name)" }
    // A and B only implement Scope; C and the second A extension share their other members.
    #expect(!with.contains("A/B"))
    #expect(with == ["C/A"])
}
