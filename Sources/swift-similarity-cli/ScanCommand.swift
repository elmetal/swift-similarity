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
    
    @Flag(name: .long, help: "Use hierarchical processing pipeline for massive datasets (Phase 11)")
    var hierarchical: Bool = false
    
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
            
            // Calculate similarity using selected processing method
            let (similarPairs, performanceStats) = if hierarchical {
                try await calculateWithHierarchical(
                    elements: elements,
                    threshold: threshold,
                    optimizationLevel: optimizationLevel
                )
            } else {
                try await calculateWithOptimization(
                    elements: elements,
                    optimizationLevel: optimizationLevel
                )
            }
            
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
                
                var progressText = "\rProgress: \(percentage)%"
                if progressInfo.candidatesFound > 0 {
                    progressText += " - \(progressInfo.candidatesFound) candidates found"
                }
                if let remaining = progressInfo.estimatedTimeRemaining {
                    progressText += " - ETA: \(String(format: "%.1f", remaining))s"
                }
                
                // Use FileHandle for immediate output without buffering
                if let data = progressText.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
                
                if progressInfo.blocksProcessed == progressInfo.totalBlocks {
                    try? FileHandle.standardError.write(contentsOf: Data("\n".utf8))
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
    
    /// Calculates similarity using hierarchical processing pipeline (Phase 11)
    private func calculateWithHierarchical(
        elements: [CodeElement],
        threshold: Double,
        optimizationLevel: VectorizedPrefilteringEngine.OptimizationLevel
    ) async throws -> ([(CodeElement, CodeElement, Double)], PerformanceStatistics) {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Determine project scale and configuration
        let scale = VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: elements.count)
        let hierarchicalConfig = HierarchicalProcessor.Configuration.optimal(for: scale)
        
        // Set up progress reporting for hierarchical processing
        let progressCallback: (@Sendable (HierarchicalProcessor.HierarchicalProgress) -> Void)?
        if progress {
            progressCallback = { progressInfo in
                // Always show progress for all stages
                guard progressInfo.currentStage > 0 else { return }
                
                let completionPercentage = progressInfo.totalElements > 0 ? 
                    Int((Double(progressInfo.elementsProcessed) / Double(progressInfo.totalElements)) * 100) : 0
                
                var progressText = "\rStage \(progressInfo.currentStage): \(progressInfo.stageName) - \(completionPercentage)%"
                if progressInfo.candidatesFound > 0 {
                    progressText += " - \(progressInfo.candidatesFound) candidates"
                }
                
                // Use FileHandle for immediate output without buffering
                if let data = progressText.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
                
                if progressInfo.elementsProcessed == progressInfo.totalElements {
                    try? FileHandle.standardError.write(contentsOf: Data("\n".utf8))
                }
            }
        } else {
            progressCallback = nil
        }
        
        // Create vectorized engine configuration for hierarchical processor
        let vectorizedConfig = if optimizationLevel == .auto {
            VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: elements.count)
        } else {
            VectorizedPrefilteringEngine.Configuration(
                optimizationLevel: optimizationLevel,
                blockSize: 0,
                maxConcurrency: threads > 0 ? threads : 0
            )
        }
        
        // Initialize hierarchical processor
        let processor = HierarchicalProcessor(
            configuration: hierarchicalConfig,
            vectorizedConfig: vectorizedConfig,
            progressCallback: progressCallback
        )
        
        // Display hierarchical processing info
        print("   Project scale: \(scale.rawValue)")
        print("   Quick stage offset: +\(String(format: "%.2f", hierarchicalConfig.quickStageOffset))")
        print("   Medium stage offset: +\(String(format: "%.2f", hierarchicalConfig.mediumStageOffset))")
        print("   Max candidates per stage: \(hierarchicalConfig.maxCandidatesPerStage)")
        if hierarchicalConfig.enableSampling {
            print("   Sampling: \(String(format: "%.1f", hierarchicalConfig.samplingRatio * 100))%")
        }
        print("")
        
        // Process through hierarchical pipeline
        let (results, stageStatistics) = try await processor.process(elements: elements, threshold: threshold)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        // Convert results to expected format
        let similarPairs = results.map { (element1, element2, similarity) in
            (element1, element2, similarity)
        }
        
        // Calculate aggregate statistics
        let totalPairs = elements.count * (elements.count - 1) / 2
        let _ = stageStatistics.first?.inputCandidates ?? totalPairs // totalInputCandidates - unused
        let finalOutputCandidates = stageStatistics.last?.outputCandidates ?? similarPairs.count
        
        let prefilteringStats = PrefilteringStatistics(
            totalPossiblePairs: totalPairs,
            candidatePairs: finalOutputCandidates,
            prefilteringTimeSeconds: totalTime,
            bloomFilterStats: nil
        )
        
        let performanceStats = PerformanceStatistics(
            prefilteringStats: prefilteringStats,
            totalCalculationTime: totalTime,
            parallelProcessingTime: totalTime,
            threadsUsed: vectorizedConfig.maxConcurrency > 0 ? vectorizedConfig.maxConcurrency : ProcessInfo.processInfo.processorCount,
            peakMemoryUsage: nil,
            similarPairsFound: similarPairs.count,
            processingRate: Double(similarPairs.count) / totalTime
        )
        
        // Display stage statistics if requested
        if stats {
            showHierarchicalStatistics(stageStatistics)
        }
        
        return (similarPairs, performanceStats)
    }
    
    /// Shows detailed hierarchical processing statistics
    private func showHierarchicalStatistics(_ stageStats: [HierarchicalProcessor.StageStatistics]) {
        print("\n=== Hierarchical Processing Statistics ===")
        
        for (_, stat) in stageStats.enumerated() {
            print("\n--- Stage \(stat.stage): \(stat.name) ---")
            print("Processing time: \(String(format: "%.3f", stat.processingTime))s")
            print("Input candidates: \(stat.inputCandidates)")
            print("Output candidates: \(stat.outputCandidates)")
            print("Reduction ratio: \(String(format: "%.1f", stat.reductionRatio * 100))%")
            print("Processing rate: \(String(format: "%.1f", stat.processingRate)) candidates/sec")
        }
        
        // Summary statistics
        let totalTime = stageStats.reduce(0) { $0 + $1.processingTime }
        let firstStageInput = stageStats.first?.inputCandidates ?? 0
        let lastStageOutput = stageStats.last?.outputCandidates ?? 0
        let overallReduction = firstStageInput > 0 ? Double(firstStageInput - lastStageOutput) / Double(firstStageInput) : 0.0
        
        print("\n--- Overall Summary ---")
        print("Total processing time: \(String(format: "%.3f", totalTime))s")
        print("Overall reduction: \(String(format: "%.1f", overallReduction * 100))%")
        print("Stages completed: \(stageStats.count)")
        print("==========================================\n")
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