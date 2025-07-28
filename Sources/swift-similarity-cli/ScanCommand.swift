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
    
    @Option(name: .long, help: "Optimization level (off, conservative, balanced, aggressive, auto)")
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
        
        // Validate optimization level
        let optimizationLevel = parseOptimizationLevel(optimization)
        
        print("Scanning directory: \(directory)")
        print("Element type: \(elementType)")
        print("Threshold: \(threshold)")
        print("Advanced metrics: \(advanced)")
        if optimizationLevel != nil {
            print("Optimization: \(optimization)")
        } else {
            print("Optimization: disabled")
        }
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
            
            let similarPairs: [(CodeElement, CodeElement, Double)]
            let performanceStats: PerformanceStatistics?
            
            // Choose calculation method based on optimization settings
            if let optLevel = optimizationLevel {
                (similarPairs, performanceStats) = try calculateWithOptimization(
                    elements: elements,
                    optimizationLevel: optLevel
                )
            } else {
                (similarPairs, performanceStats) = try calculateWithoutOptimization(elements: elements)
            }
            
            print("Found \(similarPairs.count) similar pairs")
            
            // Show performance statistics if requested
            if stats, let perfStats = performanceStats {
                showPerformanceStatistics(perfStats)
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
    private func parseOptimizationLevel(_ optimization: String) -> PerformanceOptimizedConfiguration.PerformanceLevel? {
        switch optimization.lowercased() {
        case "off", "disabled", "none":
            return nil
        case "conservative":
            return .conservative
        case "balanced":
            return .balanced
        case "aggressive":
            return .aggressive
        case "auto":
            // Auto mode will be handled in calculateWithOptimization
            return .balanced
        default:
            print("Warning: Unknown optimization level '\(optimization)', using 'auto'")
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
    
    /// Calculates similarity without optimization (legacy mode)
    private func calculateWithoutOptimization(
        elements: [CodeElement]
    ) throws -> ([(CodeElement, CodeElement, Double)], PerformanceStatistics?) {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var similarPairs: [(CodeElement, CodeElement, Double)] = []
        var processedPairs = 0
        let totalPairs = elements.count * (elements.count - 1) / 2
        
        print("Using legacy calculation mode (no optimization)")
        
        // Compare all pairs of elements (original O(n²) logic)
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
                
                processedPairs += 1
                
                // Show progress for large datasets
                if progress && totalPairs > 100 && processedPairs % 100 == 0 {
                    let percentage = Int(Double(processedPairs) / Double(totalPairs) * 100)
                    print("\rProgress: \(percentage)% (\(processedPairs)/\(totalPairs))", terminator: "")
                    fflush(stdout)
                }
            }
        }
        
        if progress && totalPairs > 100 {
            print("") // New line when complete
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        // Sort by similarity score (highest first)
        similarPairs.sort { $0.2 > $1.2 }
        
        // Create basic performance statistics
        let legacyStats = PerformanceStatistics(
            prefilteringStats: PrefilteringStatistics(
                totalPossiblePairs: totalPairs,
                candidatePairs: totalPairs,
                prefilteringTimeSeconds: 0.0
            ),
            totalCalculationTime: totalTime,
            parallelProcessingTime: totalTime,
            threadsUsed: 1,
            similarPairsFound: similarPairs.count,
            processingRate: totalTime > 0 ? Double(totalPairs) / totalTime : 0
        )
        
        return (similarPairs, legacyStats)
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