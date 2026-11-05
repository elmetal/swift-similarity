import Foundation

// MARK: - Scan Statistics

/// How many pairs the exact prefilters left for the edit distance computation.
public struct PrefilteringStatistics: Sendable {
    /// Total number of possible pairs
    public let totalPossiblePairs: Int
    /// Number of candidate pairs after prefiltering
    public let candidatePairs: Int
    /// Reduction ratio (0.0-1.0, higher is better)
    public let reductionRatio: Double
    /// Time spent in prefiltering (seconds)
    public let prefilteringTimeSeconds: Double
    
    /// Creates prefiltering statistics
    public init(totalPossiblePairs: Int, candidatePairs: Int, prefilteringTimeSeconds: Double) {
        self.totalPossiblePairs = totalPossiblePairs
        self.candidatePairs = candidatePairs
        self.reductionRatio = totalPossiblePairs > 0 ? 1.0 - (Double(candidatePairs) / Double(totalPossiblePairs)) : 0.0
        self.prefilteringTimeSeconds = prefilteringTimeSeconds
    }
}

/// Timing and throughput of a scan, reported by `scan --stats`.
public struct PerformanceStatistics: Sendable {
    /// Prefiltering statistics
    public let prefilteringStats: PrefilteringStatistics
    /// Total calculation time (seconds)
    public let totalCalculationTime: Double
    /// Parallel processing time (seconds)
    public let parallelProcessingTime: Double
    /// Number of threads used
    public let threadsUsed: Int
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
        similarPairsFound: Int,
        processingRate: Double
    ) {
        self.prefilteringStats = prefilteringStats
        self.totalCalculationTime = totalCalculationTime
        self.parallelProcessingTime = parallelProcessingTime
        self.threadsUsed = threadsUsed
        self.similarPairsFound = similarPairsFound
        self.processingRate = processingRate
    }
    
    /// Overall performance improvement ratio compared to naive O(n²) approach
    public var performanceImprovement: Double {
        let naivePairs = prefilteringStats.totalPossiblePairs
        let actualPairs = prefilteringStats.candidatePairs
        return naivePairs > 0 && actualPairs > 0 ? Double(naivePairs) / Double(actualPairs) : 1.0
    }
}
