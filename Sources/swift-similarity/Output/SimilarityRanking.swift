import Foundation

// MARK: - Ranking

/// Orders similar pairs for reporting.
public enum SimilarityRanking {
    /// How similar pairs are ordered.
    public enum SortOrder: String, CaseIterable, Sendable {
        /// By similarity, highest first.
        case similarity
        /// By impact (similarity × lines), highest first, so large duplicates come before small ones.
        case priority
    }

    /// Number of source lines a declaration spans (`endLine - startLine + 1`, at least 1).
    public static func lineSpan(of element: CodeElement) -> Int {
        max(1, element.endLine - element.startLine + 1)
    }

    /// Lines counted for the priority of a pair: the line span of the smaller declaration.
    ///
    /// At most that many lines can be duplicated, so the larger declaration's extra lines
    /// do not inflate the priority.
    public static func lines(of pair: (CodeElement, CodeElement, Double)) -> Int {
        min(lineSpan(of: pair.0), lineSpan(of: pair.1))
    }

    /// Impact of a pair: similarity (0.0-1.0) × `lines(of:)`.
    public static func priority(of pair: (CodeElement, CodeElement, Double)) -> Double {
        pair.2 * Double(lines(of: pair))
    }

    /// Sorts pairs in the given order. Ties keep the input order, so the result is deterministic
    /// as long as the input order is.
    ///
    /// - `similarity`: similarity descending.
    /// - `priority`: priority descending, then similarity descending.
    public static func sorted(
        _ pairs: [(CodeElement, CodeElement, Double)],
        by order: SortOrder
    ) -> [(CodeElement, CodeElement, Double)] {
        let keyed = pairs.enumerated().map { (index: $0.offset, pair: $0.element, priority: priority(of: $0.element)) }
        return keyed.sorted { a, b in
            if order == .priority, a.priority != b.priority {
                return a.priority > b.priority
            }
            if a.pair.2 != b.pair.2 {
                return a.pair.2 > b.pair.2
            }
            return a.index < b.index
        }.map(\.pair)
    }
}
