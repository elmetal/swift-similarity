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
    let similarity: Double
    let elementType: String
    let elementName1: String
    let elementName2: String
    let location1: CodeElementLocation
    let location2: CodeElementLocation
    let codePreview1: String
    let codePreview2: String
}

/// Scan result for JSON output
struct ScanResult: Codable {
    let summary: Summary
    let similarPairs: [SimilarPair]
    
    struct Summary: Codable {
        let totalPairs: Int
        let elementType: String
        let threshold: Double
        let advancedMetrics: Bool
    }
}