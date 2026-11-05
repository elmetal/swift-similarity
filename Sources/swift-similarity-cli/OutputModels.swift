import Foundation

// MARK: - Output Models

/// Location information for a code element
struct CodeElementLocation: Codable {
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
    let codePreview1: String
    let codePreview2: String
    /// Additional metrics, present only with `--advanced`
    let advancedMetrics: AdvancedMetrics?
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
    let similarPairs: [SimilarPair]
    
    struct Summary: Codable {
        let totalPairs: Int
        let elementType: String
        let threshold: Double
        /// Cost of a node rename in the tree edit distance (insertions and deletions cost 1)
        let renameCost: Double
        let advancedMetrics: Bool
        /// Order of `similarPairs`: "similarity" or "priority"
        let sortOrder: String
    }
}