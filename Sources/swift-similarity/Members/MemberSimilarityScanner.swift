import Foundation

// MARK: - Member Similarity Scanner

/// Finds types, protocols and extensions with similar members (`MemberSimilarity`), as
/// `scan --compare members` does.
///
/// Unlike `SimilarityScanner`, which compares whole syntax trees, this compares only the members'
/// kinds, names and types, ignoring member order, method bodies and the types' own names. It
/// finds types with the same shape, such as two DTOs with the same fields.
///
/// Only elements of the same group are compared: concrete types (struct, class, enum, actor) with
/// each other, protocols with protocols and extensions with extensions. Comparing a protocol with a
/// type would mostly find types that conform to it.
///
/// With a `ConformanceIndex`, members that satisfy a requirement of a protocol the type conforms
/// to (protocol witnesses) are left out before comparing, since every conforming type declares
/// them. A type or extension made only of witnesses has nothing left to compare.
public struct MemberSimilarityScanner: Sendable {
    /// Elements with fewer members are not compared: one shared member says little about two types.
    public static let defaultMinimumMemberCount = 2

    /// Elements with fewer members than this are skipped.
    public let minimumMemberCount: Int

    public init(minimumMemberCount: Int = defaultMinimumMemberCount) {
        self.minimumMemberCount = minimumMemberCount
    }

    /// Finds every pair of `elements` whose member similarity is at least `threshold`, most
    /// similar first, ties in the order of `elements`.
    ///
    /// - Parameter conformances: When given, protocol witnesses are left out of the members of
    ///   types and extensions (`ConformanceIndex.membersExcludingWitnesses(of:)`).
    ///
    /// Elements without members (functions and initializers) or with fewer than
    /// `minimumMemberCount` members, nested pairs and pairs from different groups are skipped.
    /// `statistics.pairsRuledOutByUpperBound` counts the pairs skipped without comparing members:
    /// those from different groups, with too few members, or whose member counts alone rule them out.
    public func scan(_ elements: [CodeElement], threshold: Double, conformances: ConformanceIndex? = nil) -> SimilarityScanner.Result {
        let startTime = ProcessInfo.processInfo.systemUptime
        let comparedMembers = elements.map { element in
            conformances.map { $0.membersExcludingWitnesses(of: element) } ?? element.members
        }
        let groups = elements.indices.map { index -> Group? in
            guard let members = comparedMembers[index], members.count >= minimumMemberCount else { return nil }
            return Group(elements[index].elementType)
        }

        struct Row: Sendable {
            var pairs: [(index: Int, similarity: Double)] = []
            var nested = 0
            var ruledOut = 0
            var compared = 0
        }
        let rows = Array(elements.indices).concurrentMap { i -> Row in
            var row = Row()
            for j in (i + 1)..<elements.count {
                guard let group = groups[i], group == groups[j] else {
                    row.ruledOut += 1
                    continue
                }
                let first = elements[i]
                let second = elements[j]
                if first.isNested(with: second) {
                    row.nested += 1
                    continue
                }
                let members1 = comparedMembers[i]!
                let members2 = comparedMembers[j]!
                guard MemberSimilarity.upperBound(count1: members1.count, count2: members2.count) >= threshold else {
                    row.ruledOut += 1
                    continue
                }
                row.compared += 1
                let similarity = MemberSimilarity.similarity(members1, members2)
                if similarity >= threshold {
                    row.pairs.append((j, similarity))
                }
            }
            return row
        }

        var indexedPairs: [(index1: Int, index2: Int, similarity: Double)] = []
        for (i, row) in rows.enumerated() {
            indexedPairs.append(contentsOf: row.pairs.map { (i, $0.index, $0.similarity) })
        }
        indexedPairs.sort {
            ($0.similarity, $1.index1, $1.index2) > ($1.similarity, $0.index1, $0.index2)
        }

        let statistics = ScanStatistics(
            elementCount: elements.count,
            totalPairs: elements.count * max(0, elements.count - 1) / 2,
            nestedPairs: rows.reduce(0) { $0 + $1.nested },
            pairsRuledOutByUpperBound: rows.reduce(0) { $0 + $1.ruledOut },
            pairsCompared: rows.reduce(0) { $0 + $1.compared },
            similarPairs: indexedPairs.count,
            workerCount: ProcessInfo.processInfo.processorCount,
            fingerprintTime: 0,
            comparisonTime: ProcessInfo.processInfo.systemUptime - startTime
        )
        return SimilarityScanner.Result(
            pairs: indexedPairs.map { (elements[$0.index1], elements[$0.index2], $0.similarity) },
            statistics: statistics
        )
    }

    /// Which elements are compared with each other.
    enum Group: Sendable, Equatable {
        case concreteType
        case `protocol`
        case `extension`

        /// nil for functions, initializers, properties and subscripts, which have no members.
        init?(_ type: CodeElementType) {
            switch type {
            case .struct, .class, .enum, .actor: self = .concreteType
            case .protocol: self = .protocol
            case .extension: self = .extension
            case .function, .initializer, .property, .subscript: return nil
            }
        }
    }
}
