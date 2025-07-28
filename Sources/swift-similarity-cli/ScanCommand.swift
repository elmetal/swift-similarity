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
    
    // MARK: - Performance Optimization Options
    
    @Option(name: .long, help: "Optimization level (conservative, balanced, aggressive, auto)")
    var optimization: String = "auto"
    
    @Flag(name: .long, help: "Show progress during similarity calculation")
    var progress: Bool = false
    
    @Option(name: .long, help: "Number of threads for parallel processing (0 for automatic)")
    var threads: Int = 0
    
    @Flag(name: .long, help: "Show detailed performance statistics")
    var stats: Bool = false
    
    func run() throws {
        // Validate element type
        guard let targetElementType = CodeElementType(rawValue: elementType) else {
            print("Error: Invalid element type '\(elementType)'. Valid types: function, struct, class, enum")
            throw ExitCode.failure
        }
        
        // Parse optimization level
        let optimizationLevel = parseOptimizationLevel(optimization)
        
        print("Scanning directory: \(directory)")
        print("Element type: \(elementType)")
        print("Threshold: \(threshold)")
        print("Advanced metrics: \(advanced)")
        print("Optimization: \(optimization)")
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
            
            // Calculate similarity using optimization engine
            let (similarPairs, performanceStats) = try calculateWithOptimization(
                elements: elements,
                optimizationLevel: optimizationLevel
            )
            
            print("Found \(similarPairs.count) similar pairs")
            
            // Show performance statistics if requested
            if stats {
                showPerformanceStatistics(performanceStats)
            }
            
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
    
    // MARK: - Helper Methods
    
    /// Parses the optimization level from command line argument
    private func parseOptimizationLevel(_ optimization: String) -> PerformanceOptimizedConfiguration.PerformanceLevel {
        switch optimization.lowercased() {
        case "conservative":
            return .conservative
        case "balanced":
            return .balanced
        case "aggressive":
            return .aggressive
        case "auto":
            return .balanced
        default:
            print("Warning: Unknown optimization level '\(optimization)', using 'balanced'")
            return .balanced
        }
    }
    
    /// Calculates similarity with performance optimization
    private func calculateWithOptimization(
        elements: [CodeElement],
        optimizationLevel: PerformanceOptimizedConfiguration.PerformanceLevel
    ) throws -> ([(CodeElement, CodeElement, Double)], PerformanceStatistics) {
        
        let config = PerformanceOptimizedConfiguration.optimized(
            elementCount: elements.count,
            useAdvancedMetrics: advanced,
            targetPerformance: optimizationLevel
        )
        
        // Override thread count if specified
        let finalConfig = PerformanceOptimizedConfiguration(
            prefilteringConfig: config.prefilteringConfig,
            similarityConfig: config.similarityConfig,
            advancedConfig: config.advancedConfig,
            concurrentThreads: threads > 0 ? threads : config.concurrentThreads,
            enableProgressReporting: progress || elements.count > 1000,
            batchSize: config.batchSize
        )
        
        let calculator = PerformanceOptimizedCalculator(configuration: finalConfig)
        
        if progress {
            return calculator.calculateSimilarityWithProgress(
                elements: elements,
                threshold: threshold
            ) { progressInfo in
                let percentage = Int(progressInfo.progressPercentage * 100)
                let processed = progressInfo.processedCandidates
                let total = progressInfo.totalCandidates
                
                print("\rProgress: \(percentage)% (\(processed)/\(total))", terminator: "")
                if let rate = progressInfo.processingRate {
                    print(" - \(String(format: "%.1f", rate)) pairs/sec", terminator: "")
                }
                if let remaining = progressInfo.estimatedTimeRemaining {
                    print(" - ETA: \(String(format: "%.1f", remaining))s", terminator: "")
                }
                fflush(stdout)
                
                if progressInfo.processedCandidates == progressInfo.totalCandidates {
                    print("") // New line when complete
                }
            }
        } else {
            return calculator.calculateSimilarity(elements: elements, threshold: threshold)
        }
    }
    

    
    /// Shows detailed performance statistics
    private func showPerformanceStatistics(_ stats: PerformanceStatistics) {
        print("\n=== Performance Statistics ===")
        print("Total calculation time: \(String(format: "%.3f", stats.totalCalculationTime))s")
        print("Parallel processing time: \(String(format: "%.3f", stats.parallelProcessingTime))s")
        print("Threads used: \(stats.threadsUsed)")
        print("Processing rate: \(String(format: "%.1f", stats.processingRate)) pairs/sec")
        print("Similar pairs found: \(stats.similarPairsFound)")
        
        let prefiltering = stats.prefilteringStats
        print("\n--- Prefiltering Results ---")
        print("Total possible pairs: \(prefiltering.totalPossiblePairs)")
        print("Candidate pairs: \(prefiltering.candidatePairs)")
        print("Reduction ratio: \(String(format: "%.1f", prefiltering.reductionRatio * 100))%")
        print("Prefiltering time: \(String(format: "%.3f", prefiltering.prefilteringTimeSeconds))s")
        print("Performance improvement: \(String(format: "%.1f", stats.performanceImprovement))x")
        
        if let bloomStats = prefiltering.bloomFilterStats {
            print("\n--- Bloom Filter Stats ---")
            if let size = bloomStats["size"] as? Int {
                print("Filter size: \(size) bits")
            }
            if let hashFunctions = bloomStats["hash_functions"] as? Int {
                print("Hash functions: \(hashFunctions)")
            }
            if let loadFactor = bloomStats["load_factor"] as? Double {
                print("Load factor: \(String(format: "%.3f", loadFactor))")
            }
            if let falsePositiveRate = bloomStats["estimated_false_positive_rate"] as? Double {
                print("Estimated false positive rate: \(String(format: "%.3f", falsePositiveRate * 100))%")
            }
        }
        print("==============================\n")
    }
}