import Foundation

// MARK: - Grouping

/// Groups similar pairs into sets of declarations that are all similar to each other, as
/// `scan --group` reports them.
///
/// When n declarations are copies of each other, the scan finds n(n−1)/2 pairs. Grouping shows them
/// once. Groups are built by complete linkage: pairs are taken from most to least similar, and two
/// groups are merged only if every declaration of one is similar (a reported pair) to every
/// declaration of the other. So within a group every two declarations reach the threshold, unlike
/// connected components, which can chain unrelated declarations through intermediate ones (A~B,
/// B~C, but not A~C).
///
/// A declaration belongs to one group only. Pairs between declarations of different groups are
/// returned as `pairsBetweenGroups`, so no pair is lost.
public enum SimilarityGrouping {
    public typealias Pair = (CodeElement, CodeElement, Double)

    /// Declarations that are all similar to each other.
    public struct Group {
        /// The declarations, ordered by file path and start line.
        public let members: [CodeElement]
        /// The pairs among the members (every two members form one), most similar first.
        public let pairs: [Pair]

        /// Similarity of the least similar pair of members.
        public var minimumSimilarity: Double { pairs.map(\.2).min() ?? 0 }
        /// Similarity of the most similar pair of members.
        public var maximumSimilarity: Double { pairs.map(\.2).max() ?? 0 }
        /// Line span of the smallest member: at most this many lines are duplicated per copy.
        public var lines: Int { members.map(SimilarityRanking.lineSpan(of:)).min() ?? 0 }
        /// Impact of the group: (members − 1) × `lines` × `minimumSimilarity`. Merging the copies
        /// into one would remove roughly that many lines. For two members it equals the pair's
        /// priority.
        public var priority: Double {
            Double(members.count - 1) * Double(lines) * minimumSimilarity
        }
    }

    /// Groups `pairs`, which must not contain a declaration paired with itself.
    ///
    /// - Parameter order: `similarity` orders groups by their most similar pair (then their least
    ///   similar pair, then size); `priority` by `Group.priority` (then similarity). Ties keep the
    ///   order in which the groups' first pairs appear in `pairs`. Pairs between groups are sorted
    ///   with `SimilarityRanking.sorted(_:by:)`.
    public static func group(
        _ pairs: [Pair],
        by order: SimilarityRanking.SortOrder = .similarity
    ) -> (groups: [Group], pairsBetweenGroups: [Pair]) {
        // Most similar first; ties in input order, so the result is deterministic.
        let sortedIndices = pairs.indices.sorted { (pairs[$0].2, $1) > (pairs[$1].2, $0) }

        var elements: [CodeElement] = []
        var indexOf: [ElementIdentity: Int] = [:]
        func index(of element: CodeElement) -> Int {
            let key = ElementIdentity(element)
            if let index = indexOf[key] { return index }
            indexOf[key] = elements.count
            elements.append(element)
            return elements.count - 1
        }
        let endpoints = pairs.map { (index(of: $0.0), index(of: $0.1)) }

        var similar: Set<Edge> = []
        for (a, b) in endpoints {
            similar.insert(Edge(a, b))
        }

        // Each element starts in its own group; groupOf[e] is the id of e's group.
        var groupOf = Array(elements.indices)
        var members = elements.indices.map { [$0] }
        var firstPair = Array(repeating: Int.max, count: elements.count)
        for pairIndex in sortedIndices {
            let (a, b) = endpoints[pairIndex]
            let groupA = groupOf[a]
            let groupB = groupOf[b]
            guard groupA != groupB else { continue }
            let canMerge = members[groupA].allSatisfy { x in
                members[groupB].allSatisfy { y in similar.contains(Edge(x, y)) }
            }
            guard canMerge else { continue }
            for element in members[groupB] {
                groupOf[element] = groupA
            }
            members[groupA] += members[groupB]
            members[groupB] = []
        }

        var pairsByGroup: [Int: [Pair]] = [:]
        var pairsBetweenGroups: [Pair] = []
        for (pairIndex, (a, b)) in endpoints.enumerated() {
            if groupOf[a] == groupOf[b] {
                pairsByGroup[groupOf[a], default: []].append(pairs[pairIndex])
                firstPair[groupOf[a]] = min(firstPair[groupOf[a]], pairIndex)
            } else {
                pairsBetweenGroups.append(pairs[pairIndex])
            }
        }

        let groups = pairsByGroup.keys.map { id -> (group: Group, firstPair: Int) in
            let groupMembers = members[id].map { elements[$0] }.sorted {
                ($0.filePath, $0.startLine, $0.endLine) < ($1.filePath, $1.startLine, $1.endLine)
            }
            let groupPairs = SimilarityRanking.sorted(pairsByGroup[id]!, by: .similarity)
            return (Group(members: groupMembers, pairs: groupPairs), firstPair[id])
        }
        let sortedGroups = groups.sorted { a, b in
            if order == .priority, a.group.priority != b.group.priority {
                return a.group.priority > b.group.priority
            }
            if a.group.maximumSimilarity != b.group.maximumSimilarity {
                return a.group.maximumSimilarity > b.group.maximumSimilarity
            }
            if a.group.minimumSimilarity != b.group.minimumSimilarity {
                return a.group.minimumSimilarity > b.group.minimumSimilarity
            }
            if a.group.members.count != b.group.members.count {
                return a.group.members.count > b.group.members.count
            }
            return a.firstPair < b.firstPair
        }.map(\.group)

        return (sortedGroups, SimilarityRanking.sorted(pairsBetweenGroups, by: order))
    }

    /// An unordered pair of element indices.
    private struct Edge: Hashable {
        let low: Int
        let high: Int

        init(_ a: Int, _ b: Int) {
            low = min(a, b)
            high = max(a, b)
        }
    }
}

/// Identifies a declaration across pairs (by file, position and name).
struct ElementIdentity: Hashable {
    let filePath: String
    let start: Int
    let end: Int
    let name: String

    init(_ element: CodeElement) {
        filePath = element.filePath
        start = element.byteRange?.lowerBound ?? element.startLine
        end = element.byteRange?.upperBound ?? element.endLine
        name = element.name
    }
}
