import Foundation
import ArgumentParser
import swift_similarity

// MARK: - Scan Command

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan directories and files for similar Swift declarations (functions, initializers, types, protocols, extensions)",
        discussion: """
            Settings are also read from the nearest \(SimilarityConfig.fileName) in the current directory \
            or one of its parents. Command-line options override it; see the README for the supported keys.
            """
    )
    
    @Argument(help: "Directories and .swift files to scan")
    var paths: [String]
    
    @Option(name: .long, help: ArgumentHelp("Skip files and directories matching a glob pattern (repeatable), such as 'Tests', '**/Generated/**' or '*.generated.swift'", valueName: "pattern"))
    var exclude: [String] = []
    
    @Option(name: .shortAndLong, help: "Type of code element to search (\(ScanCommand.elementTypeNames); default: \(ScanSettings.defaultElementType))")
    var elementType: String?
    
    @Option(name: .shortAndLong, help: "Similarity threshold (0.0-1.0; default: \(ScanSettings.defaultThreshold))")
    var threshold: Double?
    
    @Flag(name: .shortAndLong, help: "Also report structural, label and depth similarity for each pair (does not change which pairs are found)")
    var advanced: Bool = false
    
    @Option(name: .shortAndLong, help: "Output format (text/json)")
    var format: String = "text"
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?
    
    @Flag(name: [.customShort("p"), .customLong("print")], help: "Print code previews for similar elements")
    var showCode: Bool = false

    // MARK: - Filtering Options

    @Option(name: [.customShort("m"), .long], help: "Skip declarations shorter than this many lines (0 keeps all; default: \(ScanSettings.defaultMinLines))")
    var minLines: Int?

    @Option(name: .long, help: "Skip declarations with fewer tokens than this (0 keeps all; with --body-only, only the body's tokens count; default: \(ScanSettings.defaultMinTokens))")
    var minTokens: Int?

    @Flag(inversion: .prefixedNo, help: "Compare only bodies: code blocks of functions and initializers, member blocks of types (declarations without a body are skipped; default: off)")
    var bodyOnly: Bool?

    @Flag(inversion: .prefixedNo, help: "Skip declarations preceded by a 'similarity-ignore' comment; --no-ignore-directives compares them too (default: on)")
    var ignoreDirectives: Bool?

    // MARK: - Scoring Options

    @Option(name: .long, help: ArgumentHelp("Cost of renaming a node (changing its syntax kind) in the tree edit distance; insertions and deletions cost 1. Lower values make structural variants score higher (default: \(ScanSettings.defaultRenameCost))", valueName: "cost"))
    var renameCost: Double?
    
    // MARK: - Performance Optimization Options
    
    @Option(name: .long, help: "Deprecated, has no effect: every level schedules the work the same way (conservative, balanced, aggressive, auto)")
    var optimization: String = "auto"
    
    @Flag(name: .long, help: "Show progress during similarity calculation")
    var progress: Bool = false
    
    @Option(name: .long, help: "Number of threads for parallel processing (0 for automatic)")
    var threads: Int = 0
    
    @Flag(name: .long, help: "Show detailed performance statistics")
    var stats: Bool = false
    
    @Flag(name: .long, help: "Use hierarchical processing pipeline for massive datasets (Phase 11)")
    var hierarchical: Bool = false
    
    // MARK: - Reporting Options
    
    @Option(name: .long, help: "Result order: 'similarity' (score, highest first) or 'priority' (similarity × lines of the smaller declaration, so large duplicates come first; default: \(ScanSettings.defaultSort))")
    var sort: String?
    
    @Flag(inversion: .prefixedNo, help: "Exit with code 1 if any similar pair is found (for CI); results are still written (default: off)")
    var failOnDuplicates: Bool?
    
    mutating func validate() throws {
        for path in paths {
            do {
                try FileReader.validateInputPath(path)
            } catch {
                throw ValidationError(error.localizedDescription)
            }
        }
        applySettings(config: Self.loadConfig())
        let settings = resolvedSettings
        guard (0.0...1.0).contains(settings.threshold) else {
            throw ValidationError("Threshold must be between 0.0 and 1.0, got \(settings.threshold).")
        }
        guard Self.elementTypes(for: settings.elementType) != nil else {
            throw ValidationError("Invalid element type '\(settings.elementType)'. Valid types: \(Self.elementTypeNames)")
        }
        guard ["text", "json"].contains(format.lowercased()) else {
            throw ValidationError("Invalid output format '\(format)'. Valid formats: text, json")
        }
        guard Self.optimizationLevel(for: optimization) != nil else {
            throw ValidationError("Invalid optimization level '\(optimization)'. Valid levels: conservative, balanced, aggressive, auto")
        }
        guard settings.minLines >= 0 else {
            throw ValidationError("Minimum lines must be 0 (no limit) or more, got \(settings.minLines).")
        }
        guard settings.minTokens >= 0 else {
            throw ValidationError("Minimum tokens must be 0 (no limit) or more, got \(settings.minTokens).")
        }
        guard settings.renameCost >= 0, settings.renameCost.isFinite else {
            throw ValidationError("Rename cost must be a number 0 or more, got \(settings.renameCost).")
        }
        guard threads >= 0 else {
            throw ValidationError("Number of threads must be 0 (automatic) or more, got \(threads).")
        }
        guard SimilarityRanking.SortOrder(rawValue: settings.sort.lowercased()) != nil else {
            throw ValidationError("Invalid sort order '\(settings.sort)'. Valid orders: \(SimilarityRanking.SortOrder.allCases.map(\.rawValue).joined(separator: ", "))")
        }
    }
    
    mutating func run() async throws {
        // validate() filled in and checked these values.
        let settings = resolvedSettings
        let threshold = settings.threshold
        let minLines = settings.minLines
        let minTokens = settings.minTokens
        let bodyOnly = settings.bodyOnly
        // Option values are case-insensitive; normalize them for display and output.
        let elementType = settings.elementType.lowercased()
        format = format.lowercased()
        
        let targetElementTypes = Self.elementTypes(for: elementType)!
        let optimizationLevel = Self.optimizationLevel(for: optimization)!
        let sortOrder = SimilarityRanking.SortOrder(rawValue: settings.sort.lowercased())!
        
        printDiagnostic("Scanning: \(paths.joined(separator: ", "))")
        if !exclude.isEmpty {
            printDiagnostic("Exclude: \(exclude.joined(separator: ", "))")
        }
        printDiagnostic("Element type: \(elementType)")
        printDiagnostic("Threshold: \(threshold)")
        printDiagnostic("Minimum lines: \(minLines), minimum tokens: \(minTokens)")
        printDiagnostic("Compare: \(bodyOnly ? "bodies only" : "whole declarations")")
        printDiagnostic("Rename cost: \(settings.renameCost)")
        printDiagnostic("Advanced metrics: \(advanced)")
        printDiagnostic("Optimization: \(optimization)")
        printDiagnostic("")
        
        var pairCount = 0
        do {
            // Extract code elements from the given paths
            let extractorConfig = CodeElementExtractor.Configuration(
                elementTypes: targetElementTypes,
                maxPreviewLines: 5,
                minLines: minLines,
                minTokens: minTokens,
                respectIgnoreDirectives: settings.ignoreDirectives,
                compareBodyOnly: bodyOnly
            )
            let extractor = CodeElementExtractor(configuration: extractorConfig)
            let elements = try extractor.extractElements(fromPaths: paths, excluding: exclude.map(ExcludePattern.init))
            
            let elementDescription = elementType == "all" ? "elements (all types)" : "\(elementType) elements"
            printDiagnostic("Found \(elements.count) \(elementDescription)")
            
            // Calculate similarity using selected processing method
            let (unsortedPairs, performanceStats): ([(CodeElement, CodeElement, Double)], PerformanceStatistics?) = if elements.count < 2 {
                // Still write the (empty) result so JSON consumers always get a document.
                ([], nil)
            } else if hierarchical {
                try await calculateWithHierarchical(
                    elements: elements,
                    threshold: threshold,
                    costs: settings.operationCosts,
                    optimizationLevel: optimizationLevel
                )
            } else {
                try await calculateWithOptimization(
                    elements: elements,
                    threshold: threshold,
                    costs: settings.operationCosts,
                    optimizationLevel: optimizationLevel
                )
            }
            let similarPairs = SimilarityRanking.sorted(unsortedPairs, by: sortOrder)
            
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
                costs: settings.operationCosts,
                printCodePreviews: showCode,
                sortOrder: sortOrder
            )
            
            if format == "json" {
                try formatter.outputJSON(similarPairs: similarPairs, to: output)
            } else {
                try formatter.outputText(similarPairs: similarPairs, to: output)
            }
            
            pairCount = similarPairs.count
        } catch {
            printDiagnostic("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
        
        // Checked after the results are written, outside the do/catch so it is not reported as an error.
        if settings.failOnDuplicates && pairCount > 0 {
            printDiagnostic("Exiting with code 1: \(pairCount) similar pairs found (--fail-on-duplicates)")
            throw ExitCode.failure
        }
    }
    
    // MARK: - Helper Methods
    
    /// Reads the nearest config file, warning about problems with it on stderr.
    private static func loadConfig() -> SimilarityConfig? {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let url = SimilarityConfig.find(from: currentDirectory) else { return nil }
        do {
            let config = try SimilarityConfig.load(from: url)
            printDiagnostic("Using config: \(url.path)")
            for key in config.unknownKeys {
                printDiagnostic("Warning: \(url.path): unsupported key '\(key)' is ignored")
            }
            return config
        } catch {
            printDiagnostic("Warning: ignoring \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// The options given on the command line; nil for those that were not.
    private var commandLineSettings: SimilarityConfig {
        SimilarityConfig(
            threshold: threshold,
            elementType: elementType,
            exclude: exclude,
            minLines: minLines,
            minTokens: minTokens,
            bodyOnly: bodyOnly,
            ignoreDirectives: ignoreDirectives,
            sort: sort,
            failOnDuplicates: failOnDuplicates,
            renameCost: renameCost
        )
    }
    
    /// Every option, after applySettings filled in those not given on the command line.
    private var resolvedSettings: ScanSettings {
        ScanSettings.resolve(commandLine: commandLineSettings, file: nil)
    }
    
    /// Fills in options not given on the command line from the config file and defaults.
    private mutating func applySettings(config: SimilarityConfig?) {
        let settings = ScanSettings.resolve(commandLine: commandLineSettings, file: config)
        threshold = settings.threshold
        elementType = settings.elementType
        exclude = settings.exclude
        minLines = settings.minLines
        minTokens = settings.minTokens
        bodyOnly = settings.bodyOnly
        ignoreDirectives = settings.ignoreDirectives
        sort = settings.sort
        failOnDuplicates = settings.failOnDuplicates
        renameCost = settings.renameCost
    }
    
    /// Accepted `--element-type` values, for help and error messages.
    static let elementTypeNames = (CodeElementType.allCases.map(\.rawValue) + ["all"]).joined(separator: ", ")
    
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
        threshold: Double,
        costs: APTED.OperationCosts,
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
                    progressCallback: progressCallback,
                    costs: costs
                )
            } else {
                adaptiveConfig = VectorizedPrefilteringEngine.Configuration(
                    optimizationLevel: adaptiveConfig.optimizationLevel,
                    blockSize: adaptiveConfig.blockSize,
                    maxConcurrency: adaptiveConfig.maxConcurrency,
                    progressCallback: progressCallback,
                    costs: costs
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
                progressCallback: progressCallback,
                costs: costs
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
        costs: APTED.OperationCosts,
        optimizationLevel: VectorizedPrefilteringEngine.OptimizationLevel
    ) async throws -> ([(CodeElement, CodeElement, Double)], PerformanceStatistics) {
        
        let startTime = ProcessInfo.processInfo.systemUptime
        
        // Determine project scale and configuration
        let scale = VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: elements.count)
        let hierarchicalConfig = HierarchicalProcessor.Configuration.optimal(for: scale, costs: costs)
        
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
        let baseConfig = if optimizationLevel == .auto {
            VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: elements.count)
        } else {
            VectorizedPrefilteringEngine.Configuration(
                optimizationLevel: optimizationLevel,
                blockSize: 0,
                maxConcurrency: threads > 0 ? threads : 0
            )
        }
        let vectorizedConfig = VectorizedPrefilteringEngine.Configuration(
            optimizationLevel: baseConfig.optimizationLevel,
            blockSize: baseConfig.blockSize,
            maxConcurrency: baseConfig.maxConcurrency,
            costs: costs
        )
        
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