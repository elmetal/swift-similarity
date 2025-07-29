import Foundation
import ArgumentParser
import swift_similarity

// MARK: - Scan Command

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a directory for similar Swift code elements (functions, structs, classes, enums)"
    )
    
    @Argument(help: "Directory to scan for Swift files")
    var directory: String
    
    @Option(name: .shortAndLong, help: "Type of code element to search (function, struct, class, enum, all)")
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
    
    mutating func run() async throws {
        // Determine target element types
        let targetElementTypes: Set<CodeElementType>
        if elementType.lowercased() == "all" {
            targetElementTypes = Set(CodeElementType.allCases)
        } else {
            guard let singleElementType = CodeElementType(rawValue: elementType) else {
                print("Error: Invalid element type '\(elementType)'. Valid types: function, struct, class, enum, all")
                throw ExitCode.failure
            }
            targetElementTypes = [singleElementType]
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
                elementTypes: targetElementTypes,
                maxPreviewLines: 5
            )
            let extractor = CodeElementExtractor(configuration: extractorConfig)
            let elements = try extractor.extractElements(fromDirectory: directory)
            
            let elementDescription = elementType.lowercased() == "all" ? "elements (all types)" : "\(elementType) elements"
            print("Found \(elements.count) \(elementDescription)")
            
            if elements.count < 2 {
                print("Need at least 2 \(elementDescription) to compare")
                return
            }
            
            // Calculate similarity using optimization engine
            let (similarPairs, performanceStats) = try await calculateWithOptimization(
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
    private func parseOptimizationLevel(_ optimization: String) -> VectorizedPrefilteringEngine.OptimizationLevel {
        switch optimization.lowercased() {
        case "conservative":
            return .conservative
        case "balanced":
            return .balanced
        case "aggressive":
            return .aggressive
        case "auto":
            return .auto
        default:
            print("Warning: Unknown optimization level '\(optimization)', using 'auto'")
            return .auto
        }
    }
    
    /// Calculates similarity with performance optimization
    private func calculateWithOptimization(
        elements: [CodeElement],
        optimizationLevel: VectorizedPrefilteringEngine.OptimizationLevel
    ) async throws -> ([(CodeElement, CodeElement, Double)], PerformanceStatistics) {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create vectorized prefiltering engine configuration
        let progressCallback: (@Sendable (VectorizedPrefilteringEngine.VectorizedProgress) -> Void)?
        if progress {
            progressCallback = { progressInfo in
                let percentage = Int(progressInfo.completionPercentage)
                let processed = progressInfo.blocksProcessed
                let total = progressInfo.totalBlocks
                
                print("\rProgress: \(percentage)% (\(processed)/\(total))", terminator: "")
                if let remaining = progressInfo.estimatedTimeRemaining {
                    print(" - ETA: \(String(format: "%.1f", remaining))s", terminator: "")
                }
                fflush(stdout)
                
                if progressInfo.blocksProcessed == progressInfo.totalBlocks {
                    print("") // New line when complete
                }
            }
        } else {
            progressCallback = nil
        }
        
        // Use adaptive configuration for optimal performance (Phase 10)
        let vectorizedConfig: VectorizedPrefilteringEngine.Configuration
        if optimizationLevel == .auto {
            // Adaptive configuration based on dataset size and system resources
            var adaptiveConfig = VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: elements.count)
            
            // Override thread count if specified by user
            if threads > 0 {
                adaptiveConfig = VectorizedPrefilteringEngine.Configuration(
                    optimizationLevel: adaptiveConfig.optimizationLevel,
                    blockSize: adaptiveConfig.blockSize,
                    maxConcurrency: threads,
                    hashMatrixCacheSize: adaptiveConfig.hashMatrixCacheSize,
                    enableSIMD: adaptiveConfig.enableSIMD,
                    progressCallback: progressCallback
                )
            } else {
                adaptiveConfig = VectorizedPrefilteringEngine.Configuration(
                    optimizationLevel: adaptiveConfig.optimizationLevel,
                    blockSize: adaptiveConfig.blockSize,
                    maxConcurrency: adaptiveConfig.maxConcurrency,
                    hashMatrixCacheSize: adaptiveConfig.hashMatrixCacheSize,
                    enableSIMD: adaptiveConfig.enableSIMD,
                    progressCallback: progressCallback
                )
            }
            vectorizedConfig = adaptiveConfig
            
            // Display relevant configuration info for user
            let scale = VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: elements.count)
            print("Auto-detected: \(scale.rawValue) project, using \(vectorizedConfig.maxConcurrency) threads")
            print("")
        } else {
            // Manual configuration as before
            vectorizedConfig = VectorizedPrefilteringEngine.Configuration(
                optimizationLevel: optimizationLevel,
                blockSize: 0, // Auto-detect
                maxConcurrency: threads > 0 ? threads : 0, // Auto-detect if not specified
                hashMatrixCacheSize: 10000,
                enableSIMD: true,
                progressCallback: progressCallback
            )
        }
        
        // Use vectorized prefiltering engine for maximum performance
        let vectorizedEngine = VectorizedPrefilteringEngine(configuration: vectorizedConfig)
        let candidates = try await vectorizedEngine.findCandidates(elements: elements, threshold: threshold)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        // Create performance statistics for compatibility
        let totalPairs = elements.count * (elements.count - 1) / 2
        let candidateCount = candidates.count
        
        let prefilteringStats = PrefilteringStatistics(
            totalPossiblePairs: totalPairs,
            candidatePairs: candidateCount,
            prefilteringTimeSeconds: totalTime,
            bloomFilterStats: nil
        )
        
        let performanceStats = PerformanceStatistics(
            prefilteringStats: prefilteringStats,
            totalCalculationTime: totalTime,
            parallelProcessingTime: totalTime,
            threadsUsed: vectorizedConfig.maxConcurrency > 0 ? vectorizedConfig.maxConcurrency : ProcessInfo.processInfo.processorCount,
            peakMemoryUsage: nil,
            similarPairsFound: candidates.count,
            processingRate: Double(candidates.count) / totalTime
        )
        
        return (candidates, performanceStats)
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
        print("==============================\n")
    }
}