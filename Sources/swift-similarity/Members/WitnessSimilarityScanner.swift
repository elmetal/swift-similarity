import Foundation

// MARK: - Witness

/// A member that may implement a protocol requirement, collected by `CodeElementExtractor` when
/// `Configuration.witnessCandidateTypes` asks for it. Whether it does depends on the conformances of
/// every scanned file, so `WitnessSimilarityScanner` decides that once all files are extracted.
public struct WitnessCandidate: Sendable {
    /// The member, compared by its body. Its name is `Type.member`, as in `User.label` or
    /// `Team.hash(into:)`.
    public let element: CodeElement
    /// Simple name of the type or protocol that declares the member, or that its extension extends
    public let typeName: String
    /// The member's kind, name and type, matched against protocol requirements
    public let member: TypeMember

    public init(element: CodeElement, typeName: String, member: TypeMember) {
        self.element = element
        self.typeName = typeName
        self.member = member
    }
}

/// The protocol requirement a member implements (a protocol witness).
public struct Witness: Sendable, Hashable {
    /// The protocol declaring the requirement
    public let protocolName: String
    /// The requirement's name, as in `label` or `hash(into:)`
    public let requirementName: String
    /// The type implementing it; the protocol itself for a default implementation in one of its
    /// extensions
    public let typeName: String

    public init(protocolName: String, requirementName: String, typeName: String) {
        self.protocolName = protocolName
        self.requirementName = requirementName
        self.typeName = typeName
    }

    /// `Protocol.requirement`
    public var requirement: String { "\(protocolName).\(requirementName)" }

    /// Whether this is a default implementation in an extension of the protocol.
    public var isDefaultImplementation: Bool { typeName == protocolName }

    /// What to do about similar implementations of one requirement, or nil unless every element is
    /// a witness of the same requirement.
    public static func advice(for elements: [CodeElement]) -> String? {
        guard let first = elements.first?.witness,
              elements.allSatisfy({ $0.witness?.protocolName == first.protocolName && $0.witness?.requirementName == first.requirementName })
        else { return nil }
        if elements.contains(where: { $0.witness!.isDefaultImplementation }) {
            return "\(first.requirement) has a default implementation in an extension of \(first.protocolName) that the conforming types repeat; their implementations may be unnecessary"
        }
        return "\(elements.count == 2 ? "both" : "all") implement \(first.requirement); consider a default implementation in an extension of \(first.protocolName)"
    }
}

// MARK: - Witness Similarity Scanner

/// Finds similar implementations of the same protocol requirement, as `scan --compare witnesses`
/// does: code that could become one default implementation in an extension of the protocol, or
/// that repeats a default implementation that already exists.
///
/// A candidate is a witness when its type conforms (directly, through an extension in the scanned
/// files, or through protocol inheritance) to a protocol declared in the scanned files with a
/// requirement of the same kind, `static` and name. Members of a protocol's own extensions that
/// match one of its requirements are its default implementations and are compared too.
/// Requirements of standard library protocols are not compared: they cannot have one default
/// implementation for the scanned types.
///
/// Only witnesses of the same requirement are compared with each other, by the TSED of their
/// bodies (`SimilarityScanner`). The requirement fixes the name and signature, so only the code
/// differs.
public struct WitnessSimilarityScanner: Sendable {
    /// Compares the witnesses of each requirement.
    public let scanner: SimilarityScanner

    public init(scanner: SimilarityScanner = SimilarityScanner()) {
        self.scanner = scanner
    }

    /// The candidates that implement a requirement of a protocol declared in the scanned files,
    /// with `witness` set, grouped by requirement in order of their first candidate. A member that
    /// matches requirements of several protocols is assigned to the first protocol by name.
    public static func witnessesByRequirement(_ candidates: [WitnessCandidate], conformances: ConformanceIndex) -> [[CodeElement]] {
        struct Key: Hashable { let protocolName: String; let requirement: ConformanceIndex.Requirement }
        var requirementsByType: [String: [ConformanceIndex.Requirement: Set<String>]] = [:]
        var groups: [[CodeElement]] = []
        var groupIndex: [Key: Int] = [:]
        for candidate in candidates {
            let declared = requirementsByType[candidate.typeName] ?? conformances.declaredRequirements(forTypeNamed: candidate.typeName)
            requirementsByType[candidate.typeName] = declared
            let requirement = ConformanceIndex.Requirement(witness: candidate.member)
            guard let protocolName = declared[requirement]?.min() else { continue }
            var element = candidate.element
            element.witness = Witness(protocolName: protocolName, requirementName: candidate.member.name, typeName: candidate.typeName)
            let key = Key(protocolName: protocolName, requirement: requirement)
            if let index = groupIndex[key] {
                groups[index].append(element)
            } else {
                groupIndex[key] = groups.count
                groups.append([element])
            }
        }
        return groups
    }

    /// Finds every pair of witnesses of the same requirement whose bodies have a TSED score of at
    /// least `threshold`, most similar first, ties by requirement and then candidate order.
    /// Statistics count only the pairs within each requirement. `maxPairs` and `include` select the
    /// reported pairs as in `SimilarityScanner.scan`.
    public func scan(
        _ candidates: [WitnessCandidate],
        threshold: Double,
        conformances: ConformanceIndex,
        maxPairs: Int? = nil,
        including include: SimilarityScanner.PairPredicate? = nil
    ) async throws -> SimilarityScanner.Result {
        let groups = Self.witnessesByRequirement(candidates, conformances: conformances)
        var pairs: [SimilarityScanner.Pair] = []
        var elementCount = 0, totalPairs = 0, nested = 0, ruledOut = 0, compared = 0
        var distinctTrees = 0, identical = 0, similar = 0, matching = 0
        var fingerprintTime = 0.0, comparisonTime = 0.0
        for group in groups {
            elementCount += group.count
            guard group.count >= 2 else {
                distinctTrees += group.count
                continue
            }
            // Each requirement keeps at most `maxPairs`, so the most similar overall are among them.
            let result = try await scanner.scan(group, threshold: threshold, maxPairs: maxPairs, including: include)
            pairs.append(contentsOf: result.pairs)
            matching += result.matchingPairCount
            let statistics = result.statistics
            distinctTrees += statistics.distinctTreeCount
            identical += statistics.identicalPairs
            similar += statistics.similarPairs
            totalPairs += statistics.totalPairs
            nested += statistics.nestedPairs
            ruledOut += statistics.pairsRuledOutByUpperBound
            compared += statistics.pairsCompared
            fingerprintTime += statistics.fingerprintTime
            comparisonTime += statistics.comparisonTime
        }
        // Stable: requirement order, then the scanner's order within each requirement.
        let ordered = pairs.enumerated().sorted { ($1.element.similarity, $0.offset) < ($0.element.similarity, $1.offset) }.map(\.element)
        return SimilarityScanner.Result(
            pairs: Array(ordered.prefix(maxPairs ?? ordered.count)),
            statistics: ScanStatistics(
                elementCount: elementCount,
                totalPairs: totalPairs,
                nestedPairs: nested,
                pairsRuledOutByUpperBound: ruledOut,
                pairsCompared: compared,
                similarPairs: similar,
                workerCount: scanner.workerCount,
                fingerprintTime: fingerprintTime,
                comparisonTime: comparisonTime,
                distinctTreeCount: distinctTrees,
                identicalPairs: identical
            ),
            matchingPairCount: matching
        )
    }
}
