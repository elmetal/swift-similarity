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
    
    @Flag(name: .shortAndLong, help: "Also report structural, label and depth similarity for each pair (does not change which pairs are found)")
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
    
    func validate() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ValidationError("'\(directory)' is not a directory.")
        }
        guard (0.0...1.0).contains(threshold) else {
            throw ValidationError("Threshold must be between 0.0 and 1.0, got \(threshold).")
        }
        guard Self.elementTypes(for: elementType) != nil else {
            throw ValidationError("Invalid element type '\(elementType)'. Valid types: function, struct, class, enum, all")
        }
        guard ["text", "json"].contains(format.lowercased()) else {
            throw ValidationError("Invalid output format '\(format)'. Valid formats: text, json")
        }
        guard Self.optimizationLevel(for: optimization) != nil else {
            throw ValidationError("Invalid optimization level '\(optimization)'. Valid levels: conservative, balanced, aggressive, auto")
        }
        guard threads >= 0 else {
            throw ValidationError("Number of threads must be 0 (automatic) or more, got \(threads).")
        }
    }
    
    mutating func run() async throws {
        // Option values are case-insensitive; normalize them for display and output.
        elementType = elementType.lowercased()
        format = format.lowercased()
        
        // Both values were checked by validate().
        let targetElementTypes = Self.elementTypes(for: elementType)!
        let optimizationLevel = Self.optimizationLevel(for: optimization)!
        
        printDiagnostic("Scanning directory: \(directory)")
        printDiagnostic("Element type: \(elementType)")
        printDiagnostic("Threshold: \(threshold)")
        printDiagnostic("Advanced metrics: \(advanced)")
        printDiagnostic("Optimization: \(optimization)")
        printDiagnostic("")
        
        do {
            // Extract code elements from directory
            let extractorConfig = CodeElementExtractor.Configuration(
                elementTypes: targetElementTypes,
                maxPreviewLines: 5
            )
            let extractor = CodeElementExtractor(configuration: extractorConfig)
            let elements = try extractor.extractElements(fromDirectory: directory)
            
            let elementDescription = elementType == "all" ? "elements (all types)" : "\(elementType) elements"
            printDiagnostic("Found \(elements.count) \(elementDescription)")
            
            // Calculate similarity using selected processing method
            let (similarPairs, performanceStats): ([(CodeElement, CodeElement, Double)], PerformanceStatistics?) = if elements.count < 2 {
                // Still write the (empty) result so JSON consumers always get a document.
                ([], nil)
            } else if hierarchical {
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
            
            printDiagnostic("Found \(similarPairs.count) similar pairs")
            
            // Show performance statistics if requested
            if elements.count < 2 {
                printDiagnostic("Need at least 2 \(elementDescription) to compare")
            }
            
            // Show performance statistics if requested
            if stats, let performanceStats {
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
                try formatter.outputText(similarPairs: similarPairs, to: output)
            }
            
        } catch {
            printDiagnostic("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
    
    // MARK: - Helper Methods
    
    /// The element types selected by `--element-type`, or nil if the value is unknown.
    private static func elementTypes(for value: String) -> Set<CodeElementType>? {
        let value = value.lowercased()
        if value == "all" {
            return Set(CodeElementType.allCases)
        }
        return CodeElementType(rawValue: value).map { [$0] }
    }
    
    /// The optimization level selected by `--optimization`, or nil if the value is unknown.
    private static func optimizationLevel(for value: String) -> VectorizedPrefilteringEngine.OptimizationLevel? {
        VectorizedPrefilteringEngine.OptimizationLevel(rawValue: value.lowercased())
    }
    
    /// Calculates similarity with performance optimization
    private func calculateWithOptimization(
        elements: [CodeElement],
        optimizationLevel: VectorizedPrefilteringEngine.OptimizationLevel
    ) async throws -> ([(CodeElement, CodeElement, Double)], PerformanceStatistics) {
        
        let startTime = ProcessInfo.processInfo.systemUptime
        
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
                    progressCallback: progressCallback
                )
            } else {
                adaptiveConfig = VectorizedPrefilteringEngine.Configuration(
                    optimizationLevel: adaptiveConfig.optimizationLevel,
                    blockSize: adaptiveConfig.blockSize,
                    maxConcurrency: adaptiveConfig.maxConcurrency,
                    progressCallback: progressCallback
                )
            }
            vectorizedConfig = adaptiveConfig
            
            // Display relevant configuration info for user
            let scale = VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: elements.count)
            printDiagnostic("Auto-detected: \(scale.rawValue) project, using \(vectorizedConfig.maxConcurrency) threads")
            printDiagnostic("")
        } else {
            // Manual configuration as before
            vectorizedConfig = VectorizedPrefilteringEngine.Configuration(
                optimizationLevel: optimizationLevel,
                blockSize: 0, // Auto-detect
                maxConcurrency: threads > 0 ? threads : 0, // Auto-detect if not specified
                progressCallback: progressCallback
            )
        }
        
        // Use vectorized prefiltering engine for maximum performance
        let vectorizedEngine = VectorizedPrefilteringEngine(configuration: vectorizedConfig)
        let candidates = try await vectorizedEngine.findCandidates(elements: elements, threshold: threshold)
        
        let endTime = ProcessInfo.processInfo.systemUptime
        let totalTime = endTime - startTime
        
        // Create performance statistics for compatibility
        let totalPairs = elements.count * (elements.count - 1) / 2
        let candidateCount = candidates.count
        
        let prefilteringStats = PrefilteringStatistics(
            totalPossiblePairs: totalPairs,
            candidatePairs: candidateCount,
            prefilteringTimeSeconds: totalTime
        )
        
        let performanceStats = PerformanceStatistics(
            prefilteringStats: prefilteringStats,
            totalCalculationTime: totalTime,
            parallelProcessingTime: totalTime,
            threadsUsed: vectorizedConfig.maxConcurrency > 0 ? vectorizedConfig.maxConcurrency : ProcessInfo.processInfo.processorCount,
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
        
        let startTime = ProcessInfo.processInfo.systemUptime
        
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
        printDiagnostic("   Project scale: \(scale.rawValue)")
        if hierarchicalConfig.maxCandidatesPerStage > 0 {
            printDiagnostic("   Max candidates per stage: \(hierarchicalConfig.maxCandidatesPerStage)")
        }
        if hierarchicalConfig.enableSampling {
            printDiagnostic("   Sampling: \(String(format: "%.1f", hierarchicalConfig.samplingRatio * 100))%")
        }
        printDiagnostic("")
        
        // Process through hierarchical pipeline
        let (results, stageStatistics) = try await processor.process(elements: elements, threshold: threshold)
        
        let endTime = ProcessInfo.processInfo.systemUptime
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
            prefilteringTimeSeconds: totalTime
        )
        
        let performanceStats = PerformanceStatistics(
            prefilteringStats: prefilteringStats,
            totalCalculationTime: totalTime,
            parallelProcessingTime: totalTime,
            threadsUsed: vectorizedConfig.maxConcurrency > 0 ? vectorizedConfig.maxConcurrency : ProcessInfo.processInfo.processorCount,
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
        printDiagnostic("\n=== Hierarchical Processing Statistics ===")
        
        for (_, stat) in stageStats.enumerated() {
            printDiagnostic("\n--- Stage \(stat.stage): \(stat.name) ---")
            printDiagnostic("Processing time: \(String(format: "%.3f", stat.processingTime))s")
            printDiagnostic("Input candidates: \(stat.inputCandidates)")
            printDiagnostic("Output candidates: \(stat.outputCandidates)")
            printDiagnostic("Reduction ratio: \(String(format: "%.1f", stat.reductionRatio * 100))%")
            printDiagnostic("Processing rate: \(String(format: "%.1f", stat.processingRate)) candidates/sec")
        }
        
        // Summary statistics
        let totalTime = stageStats.reduce(0) { $0 + $1.processingTime }
        let firstStageInput = stageStats.first?.inputCandidates ?? 0
        let lastStageOutput = stageStats.last?.outputCandidates ?? 0
        let overallReduction = firstStageInput > 0 ? Double(firstStageInput - lastStageOutput) / Double(firstStageInput) : 0.0
        
        printDiagnostic("\n--- Overall Summary ---")
        printDiagnostic("Total processing time: \(String(format: "%.3f", totalTime))s")
        printDiagnostic("Overall reduction: \(String(format: "%.1f", overallReduction * 100))%")
        printDiagnostic("Stages completed: \(stageStats.count)")
        printDiagnostic("==========================================\n")
    }

    /// Shows detailed performance statistics
    private func showPerformanceStatistics(_ stats: PerformanceStatistics) {
        printDiagnostic("\n=== Performance Statistics ===")
        printDiagnostic("Total calculation time: \(String(format: "%.3f", stats.totalCalculationTime))s")
        printDiagnostic("Parallel processing time: \(String(format: "%.3f", stats.parallelProcessingTime))s")
        printDiagnostic("Threads used: \(stats.threadsUsed)")
        printDiagnostic("Processing rate: \(String(format: "%.1f", stats.processingRate)) pairs/sec")
        printDiagnostic("Similar pairs found: \(stats.similarPairsFound)")
        
        let prefiltering = stats.prefilteringStats
        printDiagnostic("\n--- Prefiltering Results ---")
        printDiagnostic("Total possible pairs: \(prefiltering.totalPossiblePairs)")
        printDiagnostic("Candidate pairs: \(prefiltering.candidatePairs)")
        printDiagnostic("Reduction ratio: \(String(format: "%.1f", prefiltering.reductionRatio * 100))%")
        printDiagnostic("Prefiltering time: \(String(format: "%.3f", prefiltering.prefilteringTimeSeconds))s")
        printDiagnostic("Performance improvement: \(String(format: "%.1f", stats.performanceImprovement))x")
        printDiagnostic("==============================\n")
    }
}