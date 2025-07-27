import Foundation
import ArgumentParser
import swift_similarity

// MARK: - Main CLI Tool

@main
struct SwiftSimilarityCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-similarity",
        abstract: "A Swift code similarity detection tool for finding similar functions, structs, and classes",
        version: "1.0.0",
        subcommands: [ScanCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}



// MARK: - Scan Command

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a directory for similar Swift code elements (functions, structs, classes, enums)"
    )
    
    @Argument(help: "Directory to scan for Swift files")
    var directory: String
    
    @Option(name: .shortAndLong, help: "Type of code element to search (function, struct, class, enum)")
    var elementType: String = "function"
    
    @Option(name: .shortAndLong, help: "Similarity threshold (0.0-1.0)")
    var threshold: Double = 0.8
    
    @Flag(name: .shortAndLong, help: "Use advanced similarity metrics")
    var advanced: Bool = false
    
    @Option(name: .shortAndLong, help: "Output format (text/json)")
    var format: String = "text"
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?
    
    func run() throws {
        // Validate element type
        guard let targetElementType = CodeElementType(rawValue: elementType) else {
            print("Error: Invalid element type '\(elementType)'. Valid types: function, struct, class, enum")
            throw ExitCode.failure
        }
        
        print("Scanning directory: \(directory)")
        print("Element type: \(elementType)")
        print("Threshold: \(threshold)")
        print("Advanced metrics: \(advanced)")
        print("")
        
        do {
            // Extract code elements from directory
            let extractorConfig = CodeElementExtractor.Configuration(
                elementTypes: [targetElementType],
                maxPreviewLines: 5
            )
            let extractor = CodeElementExtractor(configuration: extractorConfig)
            let elements = try extractor.extractElements(fromDirectory: directory)
            
            print("Found \(elements.count) \(elementType) elements")
            
            if elements.count < 2 {
                print("Need at least 2 \(elementType) elements to compare")
                return
            }
            
            var similarPairs: [(CodeElement, CodeElement, Double)] = []
            
            // Compare all pairs of elements
            for i in 0..<elements.count {
                for j in (i+1)..<elements.count {
                    let element1 = elements[i]
                    let element2 = elements[j]
                    
                    // Skip comparing elements in the same file with the same name
                    if element1.filePath == element2.filePath && element1.name == element2.name {
                        continue
                    }
                    
                    let similarityScore: Double
                    
                    if advanced {
                        let metrics = AdvancedSimilarityMetrics()
                        let result = metrics.calculateAdvancedSimilarity(between: element1.treeNode, and: element2.treeNode)
                        similarityScore = result.overallSimilarity
                    } else {
                        let calculator = SimilarityCalculator()
                        let result = calculator.calculateSimilarity(between: element1.treeNode, and: element2.treeNode)
                        similarityScore = result.similarityScore
                    }
                    
                    if similarityScore >= threshold {
                        similarPairs.append((element1, element2, similarityScore))
                    }
                }
            }
            
            // Sort by similarity score (highest first)
            similarPairs.sort { $0.2 > $1.2 }
            
            if format == "json" {
                try outputJSON(similarPairs: similarPairs, to: output)
            } else {
                outputText(similarPairs: similarPairs, to: output)
            }
            
        } catch {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
    
    private func outputText(similarPairs: [(CodeElement, CodeElement, Double)], to outputFile: String?) {
        let output = generateTextOutput(similarPairs: similarPairs)
        
        if let outputFile = outputFile {
            do {
                try output.write(to: URL(fileURLWithPath: outputFile), atomically: true, encoding: .utf8)
                print("Results written to: \(outputFile)")
            } catch {
                print("Failed to write to file: \(error.localizedDescription)")
                print(output)
            }
        } else {
            print(output)
        }
    }
    
    private func outputJSON(similarPairs: [(CodeElement, CodeElement, Double)], to outputFile: String?) throws {
        struct CodeElementLocation: Codable {
            let file: String
            let startLine: Int
            let endLine: Int
        }
        
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
                    codePreview1: pair.0.codePreview,
                    codePreview2: pair.1.codePreview
                )
            }
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        if let outputFile = outputFile {
            try jsonString.write(to: URL(fileURLWithPath: outputFile), atomically: true, encoding: .utf8)
            print("JSON results written to: \(outputFile)")
        } else {
            print(jsonString)
        }
    }
    
    private func generateTextOutput(similarPairs: [(CodeElement, CodeElement, Double)]) -> String {
        var output = ""
        output += "Similar \(elementType.capitalized) Elements Found: \(similarPairs.count)\n"
        output += "Threshold: \(threshold)\n"
        output += "Advanced Metrics: \(advanced)\n"
        output += "\n"
        
        if similarPairs.isEmpty {
            output += "No similar \(elementType) elements found.\n"
        } else {
            output += "Similar Pairs (sorted by similarity):\n"
            output += String(repeating: "=", count: 60) + "\n"
            
            for (index, pair) in similarPairs.enumerated() {
                output += "\(index + 1). Similarity: \(String(format: "%.2f%%", pair.2 * 100)) - \(elementType.capitalized): \(pair.0.name)\n"
                output += "   File 1: \(pair.0.filePath):\(pair.0.startLine)-\(pair.0.endLine)\n"
                output += "   File 2: \(pair.1.filePath):\(pair.1.startLine)-\(pair.1.endLine)\n"
                output += "   Code Preview 1:\n"
                output += "   \(pair.0.codePreview.replacingOccurrences(of: "\n", with: "\n   "))\n"
                output += "   Code Preview 2:\n"
                output += "   \(pair.1.codePreview.replacingOccurrences(of: "\n", with: "\n   "))\n"
                output += "\n"
            }
        }
        
        return output
    }
}