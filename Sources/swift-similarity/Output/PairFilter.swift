import Foundation

// MARK: - Pair Filter

/// Keeps the similar pairs that involve a declaration of interest, as `scan --filter-name` and
/// `--filter-code` do: "what else looks like this function?".
///
/// A declaration matches when its name contains `nameContains` (ignoring case) and its source
/// contains `codeContains` (case-sensitive); a filter that is nil matches everything. A pair is
/// kept when either of its declarations matches. Scores are unchanged: the filter only selects
/// which pairs are reported.
public struct PairFilter: Sendable, Equatable {
    /// Substring of the declaration name, ignoring case
    public let nameContains: String?
    /// Substring of the declaration's source text, case-sensitive
    public let codeContains: String?

    public init(nameContains: String? = nil, codeContains: String? = nil) {
        self.nameContains = nameContains.flatMap { $0.isEmpty ? nil : $0 }
        self.codeContains = codeContains.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Whether the filter keeps every pair.
    public var isEmpty: Bool {
        nameContains == nil && codeContains == nil
    }

    /// Whether `element` is a declaration of interest.
    public func matches(_ element: CodeElement) -> Bool {
        if let nameContains, element.name.range(of: nameContains, options: .caseInsensitive) == nil {
            return false
        }
        if let codeContains, !element.signature.contains(codeContains) {
            return false
        }
        return true
    }

    /// Whether a pair is kept: at least one of its declarations matches.
    public func includes(_ first: CodeElement, _ second: CodeElement) -> Bool {
        isEmpty || matches(first) || matches(second)
    }

    /// The predicate for `SimilarityScanner.scan(_:threshold:maxPairs:including:)`, nil when the
    /// filter keeps every pair.
    public var predicate: SimilarityScanner.PairPredicate? {
        isEmpty ? nil : { @Sendable [self] in includes($0, $1) }
    }

    /// The pairs in which at least one declaration matches, in their original order.
    public func apply(to pairs: [SimilarityScanner.Pair]) -> [SimilarityScanner.Pair] {
        isEmpty ? pairs : pairs.filter { includes($0.first, $0.second) }
    }
}
