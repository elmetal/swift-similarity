import Foundation
import swift_similarity

// MARK: - Output Formatter

/// Handles output formatting for scan results
struct OutputFormatter {
    let elementType: String
    let threshold: Double
    let advanced: Bool
    let printCodePreviews: Bool
    
    /// Computes the additional metrics for a pair when `--advanced` is set.
    /// They are reported alongside the TSED score and do not affect which pairs are found.
    private func advancedMetrics(for pair: (CodeElement, CodeElement, Double)) -> AdvancedMetrics? {
        guard advanced else { return nil }
        let result = AdvancedSimilarityMetrics().calculateAdvancedSimilarity(between: pair.0.treeNode, and: pair.1.treeNode)
        return AdvancedMetrics(
            structural: result.structuralSimilarity * 100,
            label: result.labelSimilarity * 100,
            depth: result.depthSimilarity * 100,
            combined: result.overallSimilarity * 100
        )
    }
    
    /// Outputs results in text format
    func outputText(similarPairs: [(CodeElement, CodeElement, Double)], to outputFile: String?) throws {
        let output = generateTextOutput(similarPairs: similarPairs)
        
        if let outputFile = outputFile {
            try output.write(to: URL(fileURLWithPath: outputFile), atomically: true, encoding: .utf8)
            printDiagnostic("Results written to: \(outputFile)")
        } else {
            print(output)
        }
    }
    
    /// Outputs results in JSON format
    func outputJSON(similarPairs: [(CodeElement, CodeElement, Double)], to outputFile: String?) throws {
        let result = ScanResult(
            summary: ScanResult.Summary(
                totalPairs: similarPairs.count,
                elementType: elementType,
                threshold: threshold,
                advancedMetrics: advanced
            ),
            similarPairs: similarPairs.map { pair in
                SimilarPair(
                    similarity: pair.2 * 100,
                    elementType: pair.0.elementType.rawValue,
                    elementName1: pair.0.name,
                    elementName2: pair.1.name,
                    location1: CodeElementLocation(
                        file: pair.0.filePath,
                        startLine: pair.0.startLine,
                        endLine: pair.0.endLine
                    ),
                    location2: CodeElementLocation(
                        file: pair.1.filePath,
                        startLine: pair.1.startLine,
                        endLine: pair.1.endLine
                    ),
                    codePreview1: printCodePreviews ? pair.0.codePreview : "",
                    codePreview2: printCodePreviews ? pair.1.codePreview : "",
                    advancedMetrics: advancedMetrics(for: pair)
                )
            }
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        if let outputFile = outputFile {
            try jsonString.write(to: URL(fileURLWithPath: outputFile), atomically: true, encoding: .utf8)
            printDiagnostic("JSON results written to: \(outputFile)")
        } else {
            print(jsonString)
        }
    }
    
    /// Generates text output from similar pairs
    private func generateTextOutput(similarPairs: [(CodeElement, CodeElement, Double)]) -> String {
        var output = ""
        let elementDescription = elementType.lowercased() == "all" ? "Elements (All Types)" : "\(elementType.capitalized) Elements"
        output += "Similar \(elementDescription) Found: \(similarPairs.count)\n"
        output += "Threshold: \(threshold)\n"
        output += "Advanced Metrics: \(advanced)\n"
        output += "\n"
        
        if similarPairs.isEmpty {
            output += "No similar \(elementType) elements found.\n"
        } else {
            output += "Similar Pairs (sorted by similarity):\n"
            output += String(repeating: "=", count: 60) + "\n"
            
            for (index, pair) in similarPairs.enumerated() {
                // With --element-type all, the two elements may be of different types.
                let type1 = pair.0.elementType.rawValue.capitalized
                let type2 = pair.1.elementType.rawValue.capitalized
                let names = type1 == type2
                    ? "\(type1): \(pair.0.name) / \(pair.1.name)"
                    : "\(type1): \(pair.0.name) / \(type2): \(pair.1.name)"
                output += "\(index + 1). Similarity: \(String(format: "%.2f%%", pair.2 * 100)) - \(names)\n"
                output += "   File 1: \(pair.0.filePath):\(pair.0.startLine)-\(pair.0.endLine)\n"
                output += "   File 2: \(pair.1.filePath):\(pair.1.startLine)-\(pair.1.endLine)\n"
                
                if let metrics = advancedMetrics(for: pair) {
                    output += "   Metrics: structural \(String(format: "%.2f%%", metrics.structural))"
                    output += ", label \(String(format: "%.2f%%", metrics.label))"
                    output += ", depth \(String(format: "%.2f%%", metrics.depth))"
                    output += ", combined \(String(format: "%.2f%%", metrics.combined))\n"
                }
                
                if printCodePreviews {
                    output += "   Code Preview 1:\n"
                    output += "   \(pair.0.codePreview.replacingOccurrences(of: "\n", with: "\n   "))\n"
                    output += "   Code Preview 2:\n"
                    output += "   \(pair.1.codePreview.replacingOccurrences(of: "\n", with: "\n   "))\n"
                }
                
                output += "\n"
            }
        }
        
        return output
    }
}