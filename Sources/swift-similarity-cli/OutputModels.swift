import Foundation

// MARK: - Output Models

/// Location information for a code element
struct CodeElementLocation: Codable {
    /// Path relative to the current directory, or absolute for a file outside it
    let file: String
    let startLine: Int
    let endLine: Int
}

/// Similar pair information for JSON output
struct SimilarPair: Codable {
    /// Similarity in percent
    let similarity: Double
    /// Similarity (0.0-1.0) × `lines`; the key for `--sort priority`
    let priority: Double
    /// Line span of the smaller of the two declarations
    let lines: Int
    let elementType: String
    let elementName1: String
    let elementName2: String
    let location1: CodeElementLocation
    let location2: CodeElementLocation
    /// Source of the declarations; only with `--print`
    let codePreview1: String?
    let codePreview2: String?
    /// Additional metrics, present only with `--advanced`
    let advancedMetrics: AdvancedMetrics?
    /// `Protocol.requirement` both declarations implement; only with `--compare witnesses`
    let requirement: String?
    /// What to do about the similar implementations; only with `--compare witnesses`
    let advice: String?
}

/// Additional similarity metrics reported with `--advanced` (percentages)
struct AdvancedMetrics: Codable {
    /// Jaccard similarity of node shapes (number of children per node)
    let structural: Double
    /// Jaccard similarity of node labels
    let label: Double
    /// Ratio of tree depths
    let depth: Double
    /// Weighted combination of the three metrics above
    let combined: Double
}

/// Scan result for JSON output
struct ScanResult: Codable {
    let summary: Summary
    /// Every reported pair; with `--group`, only the pairs between declarations of different groups
    let similarPairs: [SimilarPair]
    /// Groups of mutually similar declarations; only with `--group` (the default)
    let groups: [SimilarGroup]?
    /// Declarations skipped because of a `similarity-ignore` comment; only with `--show-ignored`
    let ignored: [IgnoredEntry]?
    
    struct IgnoredEntry: Codable {
        let elementType: String
        let name: String
        let location: CodeElementLocation
        /// The comment containing `similarity-ignore`
        let comment: String
    }
    
    struct Summary: Codable {
        /// Similar pairs found (matching the filters), including those not listed
        let totalPairs: Int
        /// Pairs found but not listed in `similarPairs` because of `--max-pairs`
        let omittedPairs: Int
        let elementType: String
        let threshold: Double
        /// What was compared: "tree" (TSED), "members" or "witnesses" (TSED of bodies)
        let compare: String
        /// Cost of a node rename in the tree edit distance (insertions and deletions cost 1);
        /// absent with `compare` "members", which has no edit distance
        let renameCost: Double?
        let advancedMetrics: Bool
        /// Order of `similarPairs`: "similarity" or "priority"
        let sortOrder: String
        /// Whether pairs are grouped (`--group`): `groups` is present and `similarPairs` lists
        /// only the pairs between groups
        let grouped: Bool
    }
}
/// Declarations that are all similar to each other, for JSON output with `--group`
struct SimilarGroup: Codable {
    /// Similarity of the least similar pair of members (percent)
    let minimumSimilarity: Double
    /// Similarity of the most similar pair of members (percent)
    let maximumSimilarity: Double
    /// (members − 1) × lines × minimum similarity (0.0-1.0)
    let priority: Double
    /// Line span of the smallest member
    let lines: Int
    /// `Protocol.requirement` every member implements; only with `--compare witnesses`
    let requirement: String?
    /// What to do about the similar implementations; only with `--compare witnesses`
    let advice: String?
    let members: [Member]
    
    struct Member: Codable {
        let elementType: String
        let name: String
        let location: CodeElementLocation
        /// Source of the declaration; only with `--print`
        let codePreview: String?
    }
}
