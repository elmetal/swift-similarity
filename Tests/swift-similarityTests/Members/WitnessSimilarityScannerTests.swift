import Testing
import Foundation
@testable import swift_similarity

private let witnessTypes: Set<CodeElementType> = [.function, .initializer, .property, .subscript]

private func witnessConfiguration(_ types: Set<CodeElementType> = witnessTypes, minLines: Int = 0) -> CodeElementExtractor.Configuration {
    .init(elementTypes: [], minLines: minLines, witnessCandidateTypes: types)
}

/// Similar witness pairs in `source`, as "first / second" names, most similar first.
private func witnessPairs(
    in source: String,
    types: Set<CodeElementType> = witnessTypes,
    threshold: Double = 0.8
) async throws -> [SimilarityScanner.Pair] {
    let extraction = try extraction(of: source, configuration: witnessConfiguration(types))
    return try await WitnessSimilarityScanner()
        .scan(extraction.witnessCandidates, threshold: threshold, conformances: extraction.conformances)
        .pairs
}

private func names(_ pairs: [SimilarityScanner.Pair]) -> [String] {
    pairs.map { "\($0.first.name) / \($0.second.name)" }
}

private let namedSource = """
    protocol Named {
        var name: String { get }
        var label: String { get }
        func summary(prefix: String) -> String
    }

    protocol Describable: Named {
        func describe() -> String
    }

    extension Describable {
        func describe() -> String { "<\\(label)>" }
        func helper() -> String { "<\\(label)>" }
    }

    struct User: Describable {
        let name: String
        var label: String { "[\\(name)]" }
        func summary(prefix: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return prefix + ": " + trimmed.uppercased()
        }
        func describe() -> String { "<\\(label)>" }
        var unrelated: String { "[\\(name)]" }
    }

    struct Team {
        let name: String
    }

    extension Team: Named {
        var label: String { "[\\(name)]" }
        func summary(prefix: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return prefix + ": " + trimmed.uppercased()
        }
    }
    """

@Test("Implementations of the same requirement are compared, including default implementations")
func testWitnessPairs() async throws {
    let pairs = try await witnessPairs(in: namedSource)
    #expect(Set(names(pairs)) == [
        "Describable.describe() / User.describe()",
        "User.label / Team.label",
        "User.summary(prefix:) / Team.summary(prefix:)",
    ])
    let label = try #require(pairs.first { $0.first.name == "User.label" })
    #expect(label.first.elementType == .property)
    #expect(label.first.witness == Witness(protocolName: "Named", requirementName: "label", typeName: "User"))
    #expect(label.second.witness?.typeName == "Team")
    #expect(Witness.advice(for: [label.first, label.second]) == "both implement Named.label; consider a default implementation in an extension of Named")

    let describe = try #require(pairs.first { $0.second.name == "User.describe()" })
    #expect(describe.first.witness?.isDefaultImplementation == true)
    #expect(Witness.advice(for: [describe.first, describe.second])?.hasPrefix("Describable.describe() has a default implementation") == true)
}

@Test("Members that implement no requirement, or different requirements, are not compared")
func testNonWitnessesAreNotCompared() async throws {
    let extraction = try extraction(of: namedSource, configuration: witnessConfiguration())
    let groups = WitnessSimilarityScanner.witnessesByRequirement(extraction.witnessCandidates, conformances: extraction.conformances)
    let grouped = groups.map { $0.map(\.name) }
    // `unrelated` and the protocol extension's `helper()` implement nothing; `name` is stored.
    #expect(Set(grouped.flatMap { $0 }) == [
        "Describable.describe()", "User.label", "User.summary(prefix:)", "User.describe()", "Team.label", "Team.summary(prefix:)",
    ])
    #expect(grouped.allSatisfy { group in Set(group.map { $0.split(separator: ".").last! }).count == 1 })
}

@Test("Requirements of standard library protocols are not compared")
func testStandardLibraryRequirementsAreSkipped() async throws {
    let source = """
        struct A: CustomStringConvertible, Equatable {
            var description: String { "value" }
            static func == (lhs: A, rhs: A) -> Bool { true }
        }
        struct B: CustomStringConvertible, Equatable {
            var description: String { "value" }
            static func == (lhs: B, rhs: B) -> Bool { true }
        }
        """
    #expect(try await witnessPairs(in: source).isEmpty)
}

@Test("Element types choose the kinds of members; stored properties and observers have no body to compare")
func testWitnessKinds() async throws {
    let source = """
        protocol Store {
            var count: Int { get set }
            var total: Int { get }
            subscript(index: Int) -> Int { get }
            init(seed: Int)
        }
        struct A: Store {
            var count: Int = 0 { didSet { print(count) } }
            var total: Int { get { count * 2 } }
            subscript(index: Int) -> Int { index + count }
            init(seed: Int) { count = seed }
        }
        struct B: Store {
            var count: Int = 0 { didSet { print(count) } }
            var total: Int { get { count * 2 } }
            subscript(index: Int) -> Int { index + count }
            init(seed: Int) { count = seed }
        }
        """
    #expect(Set(names(try await witnessPairs(in: source))) == [
        "A.total / B.total", "A.subscript(_:) / B.subscript(_:)", "A.init(seed:) / B.init(seed:)",
    ])
    #expect(names(try await witnessPairs(in: source, types: [.subscript])) == ["A.subscript(_:) / B.subscript(_:)"])
    #expect(names(try await witnessPairs(in: source, types: [.initializer])) == ["A.init(seed:) / B.init(seed:)"])
}

@Test("Witness candidates honor similarity-ignore comments and --min-lines")
func testWitnessFilters() throws {
    let source = """
        protocol P { func run() -> Int }
        struct A: P {
            // similarity-ignore: kept on purpose
            func run() -> Int { 1 }
        }
        struct B: P {
            func run() -> Int {
                1
            }
        }
        """
    let all = try extraction(of: source, configuration: witnessConfiguration())
    #expect(all.witnessCandidates.map(\.element.name) == ["B.run()"])
    #expect(all.ignored.map(\.name) == ["A.run()"])
    #expect(all.ignored.first?.elementType == .function)
    let long = try extraction(of: source, configuration: witnessConfiguration(minLines: 4))
    #expect(long.witnessCandidates.isEmpty)
}

@Test("declaredRequirements lists only protocols declared in the scanned files, with inheritance")
func testDeclaredRequirements() throws {
    let extraction = try extraction(of: namedSource + "\nextension User: Hashable {}", configuration: witnessConfiguration())
    let requirements = extraction.conformances.declaredRequirements(forTypeNamed: "User")
    #expect(requirements[.init(kind: .property, name: "label")] == ["Named"])
    #expect(requirements[.init(kind: .method, name: "describe()")] == ["Describable"])
    #expect(requirements[.init(kind: .method, name: "hash(into:)")] == nil)
    #expect(extraction.conformances.declaredRequirements(forTypeNamed: "Describable")[.init(kind: .method, name: "describe()")] == ["Describable"])
}

@Test("--compare witnesses defaults to every kind of member and no minimum length")
func testWitnessSettingsDefaults() {
    let defaults = ScanSettings.resolve(commandLine: SimilarityConfig(compare: "witnesses"), file: nil)
    #expect(defaults.elementType == ScanSettings.defaultWitnessElementType)
    #expect(defaults.minLines == 0)
    let explicit = ScanSettings.resolve(commandLine: SimilarityConfig(minLines: 3), file: SimilarityConfig(compare: "witnesses"))
    #expect(explicit.minLines == 3)
    #expect(ScanSettings.resolve(commandLine: SimilarityConfig(), file: nil).minLines == ScanSettings.defaultMinLines)
}

@Test("Progress counts requirements instead of restarting for each of them")
func testWitnessProgress() async throws {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [SimilarityScanner.Progress] = []
        func record(_ progress: SimilarityScanner.Progress) { lock.withLock { events.append(progress) } }
        var all: [SimilarityScanner.Progress] { lock.withLock { events } }
    }
    let source = """
        protocol Named {
            var name: String { get }
            var label: String { get }
            func greet() -> String
            func only() -> String
        }
        struct User: Named {
            let name: String
            var label: String { "[\\(name)]" }
            func greet() -> String { "hi " + name }
            func only() -> String { name }
        }
        struct Team {
            let name: String
        }
        extension Team {
            var label: String { "[\\(name)]" }
            func greet() -> String { "hi " + name }
        }
        extension Team: Named {}
        """
    let extraction = try extraction(of: source, configuration: witnessConfiguration())
    let recorder = Recorder()
    let result = try await WitnessSimilarityScanner(scanner: SimilarityScanner(progressHandler: recorder.record))
        .scan(extraction.witnessCandidates, threshold: 0.8, conformances: extraction.conformances)

    // `label` and `greet()` have two implementations each; `only()` has one and is not compared.
    #expect(result.pairs.count == 2)
    #expect(result.statistics.elementCount == 5)
    #expect(recorder.all.map(\.phase) == [.comparing, .comparing])
    #expect(recorder.all.map(\.completed) == [1, 2])
    #expect(recorder.all.allSatisfy { $0.total == 2 })
    #expect(recorder.all.last?.pairsFound == 2)
}
