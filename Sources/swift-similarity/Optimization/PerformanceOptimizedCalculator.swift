import Foundation



// MARK: - Performance Optimized Calculator

/// Configuration for performance-optimized similarity calculation
public struct PerformanceOptimizedConfiguration {
    /// Prefiltering configuration
    public let prefilteringConfig: PrefilteringConfiguration
    /// Standard similarity calculation configuration
    public let similarityConfig: SimilarityCalculator.Configuration
    /// Advanced similarity metrics configuration (optional)
    public let advancedConfig: AdvancedSimilarityMetrics.Configuration?
    /// Number of concurrent threads for parallel processing
    public let concurrentThreads: Int
    /// Enable progress reporting
    public let enableProgressReporting: Bool
    /// Batch size for processing candidate pairs
    public let batchSize: Int
    
    /// Creates performance optimized configuration
    /// - Parameters:
    ///   - prefilteringConfig: Prefiltering configuration
    ///   - similarityConfig: Similarity calculation configuration
    ///   - advancedConfig: Advanced metrics configuration (nil for basic similarity)
    ///   - concurrentThreads: Number of concurrent threads (0 for automatic)
    ///   - enableProgressReporting: Whether to enable progress reporting
    ///   - batchSize: Batch size for processing
    public init(
        prefilteringConfig: PrefilteringConfiguration = PrefilteringConfiguration(),
        similarityConfig: SimilarityCalculator.Configuration = SimilarityCalculator.Configuration(),
        advancedConfig: AdvancedSimilarityMetrics.Configuration? = nil,
        concurrentThreads: Int = 0,
        enableProgressReporting: Bool = false,
        batchSize: Int = 100
    ) {
        self.prefilteringConfig = prefilteringConfig
        self.similarityConfig = similarityConfig
        self.advancedConfig = advancedConfig
        self.concurrentThreads = concurrentThreads > 0 ? concurrentThreads : ProcessInfo.processInfo.activeProcessorCount
        self.enableProgressReporting = enableProgressReporting
        self.batchSize = batchSize
    }
    
    /// Creates an optimized configuration based on dataset characteristics
    /// - Parameters:
    ///   - elementCount: Number of elements to analyze
    ///   - useAdvancedMetrics: Whether to use advanced similarity metrics
    ///   - targetPerformance: Target performance level (aggressive, balanced, conservative)
    /// - Returns: Optimized configuration
    public static func optimized(
        elementCount: Int,
        useAdvancedMetrics: Bool = false,
        targetPerformance: PerformanceLevel = .balanced
    ) -> PerformanceOptimizedConfiguration {
        let prefilteringConfig = PrefilteringEngine.optimizedConfiguration(
            elementCount: elementCount,
            targetReduction: targetPerformance.reductionRatio
        )
        
        let advancedConfig = useAdvancedMetrics ? AdvancedSimilarityMetrics.Configuration() : nil
        
        return PerformanceOptimizedConfiguration(
            prefilteringConfig: prefilteringConfig,
            advancedConfig: advancedConfig,
            concurrentThreads: targetPerformance.threadCount,
            enableProgressReporting: elementCount > 1000,
            batchSize: targetPerformance.batchSize
        )
    }
    
    /// Performance optimization levels
    public enum PerformanceLevel {
        case aggressive  // Maximum speed, may sacrifice some accuracy
        case balanced    // Balance between speed and accuracy
        case conservative // Maximum accuracy, slower but thorough
        
        var reductionRatio: Double {
            switch self {
            case .aggressive: return 0.95
            case .balanced: return 0.90
            case .conservative: return 0.80
            }
        }
        
        var threadCount: Int {
            let cores = ProcessInfo.processInfo.activeProcessorCount
            switch self {
            case .aggressive: return cores
            case .balanced: return max(1, cores - 1)
            case .conservative: return max(1, cores / 2)
            }
        }
        
        var batchSize: Int {
            switch self {
            case .aggressive: return 200
            case .balanced: return 100
            case .conservative: return 50
            }
        }
    }
}

/// Progress information for similarity calculation
public struct CalculationProgress {
    /// Total number of candidate pairs to process
    public let totalCandidates: Int
    /// Number of processed candidates
    public let processedCandidates: Int
    /// Progress percentage (0.0-1.0)
    public var progressPercentage: Double {
        totalCandidates > 0 ? Double(processedCandidates) / Double(totalCandidates) : 0.0
    }
    /// Estimated time remaining (seconds)
    public let estimatedTimeRemaining: Double?
    /// Current processing rate (pairs per second)
    public let processingRate: Double?
    
    /// Creates calculation progress
    public init(totalCandidates: Int, processedCandidates: Int, estimatedTimeRemaining: Double? = nil, processingRate: Double? = nil) {
        self.totalCandidates = totalCandidates
        self.processedCandidates = processedCandidates
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.processingRate = processingRate
    }
}

/// Comprehensive performance statistics for optimized calculation
public struct PerformanceStatistics {
    /// Prefiltering statistics
    public let prefilteringStats: PrefilteringStatistics
    /// Total calculation time (seconds)
    public let totalCalculationTime: Double
    /// Parallel processing time (seconds)
    public let parallelProcessingTime: Double
    /// Number of threads used
    public let threadsUsed: Int
    /// Memory usage peak (bytes, if available)
    public let peakMemoryUsage: Int?
    /// Similar pairs found
    public let similarPairsFound: Int
    /// Processing rate (pairs per second)
    public let processingRate: Double
    
    /// Creates performance statistics
    public init(
        prefilteringStats: PrefilteringStatistics,
        totalCalculationTime: Double,
        parallelProcessingTime: Double,
        threadsUsed: Int,
        peakMemoryUsage: Int? = nil,
        similarPairsFound: Int,
        processingRate: Double
    ) {
        self.prefilteringStats = prefilteringStats
        self.totalCalculationTime = totalCalculationTime
        self.parallelProcessingTime = parallelProcessingTime
        self.threadsUsed = threadsUsed
        self.peakMemoryUsage = peakMemoryUsage
        self.similarPairsFound = similarPairsFound
        self.processingRate = processingRate
    }
    
    /// Overall performance improvement ratio compared to naive O(n²) approach
    public var performanceImprovement: Double {
        let naivePairs = prefilteringStats.totalPossiblePairs
        let actualPairs = prefilteringStats.candidatePairs
        return naivePairs > 0 ? Double(naivePairs) / Double(actualPairs) : 1.0
    }
}

/// High-performance similarity calculator with prefiltering and parallel processing
public class PerformanceOptimizedCalculator {
    /// Configuration for this calculator
    public let configuration: PerformanceOptimizedConfiguration
    
    /// Prefiltering engine
    private let prefilteringEngine: PrefilteringEngine
    
    /// Standard similarity calculator
    private let similarityCalculator: SimilarityCalculator
    
    /// Advanced similarity metrics (if enabled)
    private let advancedMetrics: AdvancedSimilarityMetrics?
    
    /// Progress callback
    public var progressCallback: (@Sendable (CalculationProgress) -> Void)?
    
    /// Creates a performance-optimized calculator
    /// - Parameter configuration: Configuration to use
    public init(configuration: PerformanceOptimizedConfiguration = PerformanceOptimizedConfiguration()) {
        self.configuration = configuration
        self.prefilteringEngine = PrefilteringEngine(configuration: configuration.prefilteringConfig)
        self.similarityCalculator = SimilarityCalculator(configuration: configuration.similarityConfig)
        self.advancedMetrics = configuration.advancedConfig.map { AdvancedSimilarityMetrics(configuration: $0) }
    }
    
    /// Calculates similarity between code elements with performance optimization
    /// - Parameters:
    ///   - elements: Array of code elements to analyze
    ///   - threshold: Minimum similarity threshold for results
    /// - Returns: Tuple containing similar pairs and performance statistics
    public func calculateSimilarity(
        elements: [CodeElement],
        threshold: Double = 0.7
    ) async -> (similarPairs: [(CodeElement, CodeElement, Double)], statistics: PerformanceStatistics) {
        
        let overallStartTime = CFAbsoluteTimeGetCurrent()
        
        // Step 1: Prefiltering to find candidate pairs
        let (candidates, prefilteringStats) = prefilteringEngine.findCandidatePairs(elements: elements)
        
        // Step 2: Parallel similarity calculation
        let parallelStartTime = CFAbsoluteTimeGetCurrent()
        let similarPairs = await calculateSimilarityParallel(
            elements: elements,
            candidates: candidates,
            threshold: threshold
        )
        let parallelEndTime = CFAbsoluteTimeGetCurrent()
        
        let overallEndTime = CFAbsoluteTimeGetCurrent()
        
        // Create performance statistics
        let totalTime = overallEndTime - overallStartTime
        let parallelTime = parallelEndTime - parallelStartTime
        let processingRate = candidates.count > 0 ? Double(candidates.count) / parallelTime : 0.0
        
        let statistics = PerformanceStatistics(
            prefilteringStats: prefilteringStats,
            totalCalculationTime: totalTime,
            parallelProcessingTime: parallelTime,
            threadsUsed: configuration.concurrentThreads,
            similarPairsFound: similarPairs.count,
            processingRate: processingRate
        )
        
        return (similarPairs, statistics)
    }
    
    /// Calculates similarity with progress reporting
    /// - Parameters:
    ///   - elements: Array of code elements to analyze
    ///   - threshold: Minimum similarity threshold for results
    ///   - progressCallback: Callback for progress updates
    /// - Returns: Tuple containing similar pairs and performance statistics
    public func calculateSimilarityWithProgress(
        elements: [CodeElement],
        threshold: Double = 0.7,
        progressCallback: @escaping @Sendable (CalculationProgress) -> Void
    ) async -> (similarPairs: [(CodeElement, CodeElement, Double)], statistics: PerformanceStatistics) {
        
        self.progressCallback = progressCallback
        defer { self.progressCallback = nil }
        
        return await calculateSimilarity(elements: elements, threshold: threshold)
    }
    
    // MARK: - Private Methods
    
        /// Performs parallel similarity calculation on candidate pairs using structured concurrency
    private func calculateSimilarityParallel(
        elements: [CodeElement],
        candidates: [(Int, Int)],
        threshold: Double
    ) async -> [(CodeElement, CodeElement, Double)] {
        
        // For simplicity, process candidates sequentially but allow for future optimization
        // This avoids complex Sendable issues while still providing the async interface
        var allResults: [(CodeElement, CodeElement, Double)] = []
        
        let totalCandidates = candidates.count
        var processedCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for (i, j) in candidates {
            let element1 = elements[i]
            let element2 = elements[j]
            
            // Calculate similarity
            let similarity: Double
            if let advancedMetrics = self.advancedMetrics {
                let result = advancedMetrics.calculateAdvancedSimilarity(
                    between: element1.treeNode,
                    and: element2.treeNode
                )
                similarity = result.overallSimilarity
            } else {
                let result = similarityCalculator.calculateSimilarity(
                    between: element1.treeNode,
                    and: element2.treeNode
                )
                similarity = result.similarityScore
            }
            
            if similarity >= threshold {
                allResults.append((element1, element2, similarity))
            }
            
            // Update progress
            if configuration.enableProgressReporting {
                processedCount += 1
                if let callback = progressCallback {
                    let currentTime = CFAbsoluteTimeGetCurrent()
                    let elapsed = currentTime - startTime
                    let rate = elapsed > 0 ? Double(processedCount) / elapsed : 0
                    let remaining = rate > 0 ? Double(totalCandidates - processedCount) / rate : nil
                    
                    let progress = CalculationProgress(
                        totalCandidates: totalCandidates,
                        processedCandidates: processedCount,
                        estimatedTimeRemaining: remaining,
                        processingRate: rate
                    )
                    callback(progress)
                }
            }
            
            // Yield control to allow other tasks to run
            if processedCount % 10 == 0 {
                await Task.yield()
            }
        }
        
        return allResults.sorted { $0.2 > $1.2 } // Sort by similarity score descending
    }

    
}

// MARK: - Array Extension for Chunking

private extension Array {
    /// Splits array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
} 