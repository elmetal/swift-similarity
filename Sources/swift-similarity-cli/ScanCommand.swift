import Foundation
import ArgumentParser
import swift_similarity

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
    
    @Flag(name: [.customShort("p"), .customLong("print")], help: "Print code previews for similar elements")
    var showCode: Bool = false
    
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
            
            // Create output formatter
            let formatter = OutputFormatter(
                elementType: elementType,
                threshold: threshold,
                advanced: advanced,
                printCodePreviews: showCode
            )
            
            if format == "json" {
                try formatter.outputJSON(similarPairs: similarPairs, to: output)
            } else {
                formatter.outputText(similarPairs: similarPairs, to: output)
            }
            
        } catch {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}