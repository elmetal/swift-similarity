import Foundation
import swift_similarity

// MARK: - Output Formatter

/// Handles output formatting for scan results
struct OutputFormatter {
    let elementType: String
    let threshold: Double
    let advanced: Bool
    /// Tree edit operation costs used for the TSED scores
    let costs: APTED.OperationCosts
    /// What was compared ("tree" or "members")
    let compare: String
    let printCodePreviews: Bool
    let sortOrder: SimilarityRanking.SortOrder
    /// Declarations skipped by `similarity-ignore` comments, listed with `--show-ignored`; nil otherwise
    let ignored: [IgnoredDeclaration]?
    /// Report groups of mutually similar declarations (`--group`)
    let grouped: Bool
    
    /// Computes the additional metrics for a pair when `--advanced` is set.
    /// They are reported alongside the TSED score and do not affect which pairs are found.
    private func advancedMetrics(for pair: (CodeElement, CodeElement, Double)) -> AdvancedMetrics? {
        guard advanced else { return nil }
        let result = AdvancedSimilarityMetrics(configuration: .init(aptedCosts: costs)).calculateAdvancedSimilarity(between: pair.0.treeNode, and: pair.1.treeNode)
        return AdvancedMetrics(
            structural: result.structuralSimilarity * 100,
            label: result.labelSimilarity * 100,
            depth: result.depthSimilarity * 100,
            combined: result.overallSimilarity * 100
        )
    }
    
    /// Writes already formatted output to `outputFile`, or to stdout (nothing for empty output).
    func write(_ text: String, to outputFile: String?) throws {
        if let outputFile = outputFile {
            try (text.isEmpty ? "" : text + "\n").write(to: URL(fileURLWithPath: outputFile), atomically: true, encoding: .utf8)
            printDiagnostic("Results written to: \(outputFile)")
        } else if !text.isEmpty {
            print(text)
        }
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
                compare: compare,
                renameCost: compare == "tree" ? costs.substitution : nil,
                advancedMetrics: advanced,
                sortOrder: sortOrder.rawValue
            ),
            similarPairs: similarPairs.map { pair in
                SimilarPair(
                    similarity: pair.2 * 100,
                    priority: SimilarityRanking.priority(of: pair),
                    lines: SimilarityRanking.lines(of: pair),
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
            },
            groups: grouped ? SimilarityGrouping.group(similarPairs, by: sortOrder).groups.map { group in
                SimilarGroup(
                    minimumSimilarity: group.minimumSimilarity * 100,
                    maximumSimilarity: group.maximumSimilarity * 100,
                    priority: group.priority,
                    lines: group.lines,
                    members: group.members.map { member in
                        SimilarGroup.Member(
                            elementType: member.elementType.rawValue,
                            name: member.name,
                            location: CodeElementLocation(file: member.filePath, startLine: member.startLine, endLine: member.endLine),
                            codePreview: printCodePreviews ? member.codePreview : ""
                        )
                    }
                )
            } : nil,
            ignored: ignored?.map { declaration in
                ScanResult.IgnoredEntry(
                    elementType: declaration.elementType.rawValue,
                    name: declaration.name,
                    location: CodeElementLocation(
                        file: declaration.filePath,
                        startLine: declaration.startLine,
                        endLine: declaration.endLine
                    ),
                    comment: declaration.comment
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
    
    private var orderDescription: String {
        switch sortOrder {
        case .similarity: "similarity"
        case .priority: "priority = similarity × lines of the smaller declaration"
        }
    }
    
    /// One numbered pair, as listed without `--group` and between groups.
    private func pairText(_ pair: (CodeElement, CodeElement, Double), number: Int) -> String {
        var output = ""
        // With --element-type all, the two elements may be of different types.
        let type1 = pair.0.elementType.rawValue.capitalized
        let type2 = pair.1.elementType.rawValue.capitalized
        let names = type1 == type2
            ? "\(type1): \(pair.0.name) / \(pair.1.name)"
            : "\(type1): \(pair.0.name) / \(type2): \(pair.1.name)"
        output += "\(number). Similarity: \(String(format: "%.2f%%", pair.2 * 100)) - \(names)\n"
        output += "   Priority: \(String(format: "%.1f", SimilarityRanking.priority(of: pair))) (lines: \(SimilarityRanking.lines(of: pair)))\n"
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
        return output + "\n"
    }
    
    /// Groups of mutually similar declarations, then the pairs between groups (`--group`).
    private func groupedText(_ similarPairs: [(CodeElement, CodeElement, Double)]) -> String {
        let (groups, pairsBetweenGroups) = SimilarityGrouping.group(similarPairs, by: sortOrder)
        let groupOrder = switch sortOrder {
        case .similarity: "similarity"
        case .priority: "priority = (declarations − 1) × lines of the smallest × lowest similarity"
        }
        var output = "Similar Groups (\(groups.count), sorted by \(groupOrder)):\n"
        output += "Every two declarations in a group are similar.\n"
        output += String(repeating: "=", count: 60) + "\n"
        for (index, group) in groups.enumerated() {
            let similarity = group.minimumSimilarity == group.maximumSimilarity
                ? String(format: "%.2f%%", group.minimumSimilarity * 100)
                : String(format: "%.2f%%-%.2f%%", group.minimumSimilarity * 100, group.maximumSimilarity * 100)
            let types = Set(group.members.map(\.elementType))
            let kind = types.count == 1 ? Self.pluralName(of: group.members[0].elementType) : "Declarations"
            output += "\(index + 1). \(group.members.count) \(kind), similarity \(similarity)\n"
            output += "   Priority: \(String(format: "%.1f", group.priority)) (lines: \(group.lines))\n"
            for member in group.members {
                let label = types.count == 1 ? member.name : "\(member.elementType.rawValue.capitalized): \(member.name)"
                output += "   - \(label)  \(member.filePath):\(member.startLine)-\(member.endLine)\n"
                if printCodePreviews {
                    output += "     \(member.codePreview.replacingOccurrences(of: "\n", with: "\n     "))\n"
                }
            }
            output += "\n"
        }
        if !pairsBetweenGroups.isEmpty {
            output += "Similar Pairs Between Groups (\(pairsBetweenGroups.count), sorted by \(orderDescription)):\n"
            output += String(repeating: "=", count: 60) + "\n"
            for (index, pair) in pairsBetweenGroups.enumerated() {
                output += pairText(pair, number: index + 1)
            }
        }
        return output
    }
    
    /// "Functions", "Classes", "Initializers", ... for group headings.
    private static func pluralName(of type: CodeElementType) -> String {
        switch type {
        case .class: "Classes"
        case .initializer: "Initializers"
        default: type.rawValue.capitalized + "s"
        }
    }
    
    /// Generates text output from similar pairs
    private func generateTextOutput(similarPairs: [(CodeElement, CodeElement, Double)]) -> String {
        var output = ""
        let elementDescription = elementType.lowercased() == "all" ? "Elements (All Types)" : "\(elementType.capitalized) Elements"
        output += "Similar \(elementDescription) Found: \(similarPairs.count)\n"
        output += "Threshold: \(threshold)\n"
        if compare == "tree" {
            output += "Rename Cost: \(costs.substitution)\n"
        } else {
            output += "Compare: \(compare) (kind, name and type of each member)\n"
        }
        output += "Advanced Metrics: \(advanced)\n"
        output += "\n"
        
        if similarPairs.isEmpty {
            output += "No similar \(elementType) elements found.\n"
        } else if grouped {
            output += groupedText(similarPairs)
        } else {
            output += "Similar Pairs (sorted by \(orderDescription)):\n"
            output += String(repeating: "=", count: 60) + "\n"
            for (index, pair) in similarPairs.enumerated() {
                output += pairText(pair, number: index + 1)
            }
        }
        
        if let ignored {
            output += "\nIgnored Declarations (similarity-ignore): \(ignored.count)\n"
            output += String(repeating: "=", count: 60) + "\n"
            for declaration in ignored {
                output += "- \(declaration.elementType.rawValue.capitalized): \(declaration.name)\n"
                output += "   File: \(declaration.filePath):\(declaration.startLine)-\(declaration.endLine)\n"
                output += "   Comment: \(declaration.comment)\n"
            }
        }
        
        return output
    }
}