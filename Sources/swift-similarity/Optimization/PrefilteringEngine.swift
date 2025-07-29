import Foundation

// MARK: - Prefiltering Engine

/// Configuration for the prefiltering engine
public struct PrefilteringConfiguration {
    /// Bloom filter false positive rate
    public let bloomFilterFalsePositiveRate: Double
    /// Minimum fingerprint similarity threshold for candidate selection
    public let fingerprintSimilarityThreshold: Double
    /// Minimum size ratio threshold between elements
    public let sizeRatioThreshold: Double
    /// Maximum number of candidate pairs to return
    public let maxCandidatePairs: Int
    /// Whether to use bloom filter for prefiltering
    public let enableBloomFilter: Bool
    
    /// Creates prefiltering configuration
    /// - Parameters:
    ///   - bloomFilterFalsePositiveRate: Bloom filter false positive rate (default: 0.1)
    ///   - fingerprintSimilarityThreshold: Fingerprint similarity threshold (default: 0.3)
    ///   - sizeRatioThreshold: Size ratio threshold (default: 0.3)
    ///   - maxCandidatePairs: Maximum candidate pairs (default: 10000)
    ///   - enableBloomFilter: Whether to use bloom filter (default: true)
    public init(
        bloomFilterFalsePositiveRate: Double = 0.1,
        fingerprintSimilarityThreshold: Double = 0.3,
        sizeRatioThreshold: Double = 0.3,
        maxCandidatePairs: Int = 10000,
        enableBloomFilter: Bool = true
    ) {
        self.bloomFilterFalsePositiveRate = bloomFilterFalsePositiveRate
        self.fingerprintSimilarityThreshold = fingerprintSimilarityThreshold
        self.sizeRatioThreshold = sizeRatioThreshold
        self.maxCandidatePairs = maxCandidatePairs
        self.enableBloomFilter = enableBloomFilter
    }
}

/// Statistics about prefiltering performance
public struct PrefilteringStatistics {
    /// Total number of possible pairs
    public let totalPossiblePairs: Int
    /// Number of candidate pairs after prefiltering
    public let candidatePairs: Int
    /// Reduction ratio (0.0-1.0, higher is better)
    public let reductionRatio: Double
    /// Time spent in prefiltering (seconds)
    public let prefilteringTimeSeconds: Double
    /// Bloom filter statistics
    public let bloomFilterStats: [String: Any]?
    
    /// Creates prefiltering statistics
    public init(
        totalPossiblePairs: Int,
        candidatePairs: Int,
        prefilteringTimeSeconds: Double,
        bloomFilterStats: [String: Any]? = nil
    ) {
        self.totalPossiblePairs = totalPossiblePairs
        self.candidatePairs = candidatePairs
        self.reductionRatio = totalPossiblePairs > 0 ? 1.0 - (Double(candidatePairs) / Double(totalPossiblePairs)) : 0.0
        self.prefilteringTimeSeconds = prefilteringTimeSeconds
        self.bloomFilterStats = bloomFilterStats
    }
}

/// Efficient prefiltering engine for similarity candidate selection
/// Uses bloom filters and fingerprint analysis to quickly eliminate obviously dissimilar pairs
public class PrefilteringEngine {
    /// Configuration for this engine
    public let configuration: PrefilteringConfiguration
    
    /// Creates a prefiltering engine with the specified configuration
    /// - Parameter configuration: The configuration to use
    public init(configuration: PrefilteringConfiguration = PrefilteringConfiguration()) {
        self.configuration = configuration
    }
    
    /// Finds candidate pairs from a list of code elements using prefiltering
    /// - Parameter elements: Array of code elements to analyze
    /// - Returns: Tuple containing candidate pair indices and prefiltering statistics
    public func findCandidatePairs(elements: [CodeElement]) -> (candidates: [(Int, Int)], statistics: PrefilteringStatistics) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Extract fingerprints from all elements
        let fingerprints = elements.map { $0.treeNode.extractFingerprint() }
        let totalPossiblePairs = elements.count * (elements.count - 1) / 2
        
        var candidates: [(Int, Int)] = []
        var bloomFilter: OptimizedBloomFilter? = nil
        
        // Initialize bloom filter if enabled
        if configuration.enableBloomFilter && elements.count > 50 {
            bloomFilter = OptimizedBloomFilter.forASTFingerprints(
                elementCount: elements.count,
                targetAccuracy: 1.0 - configuration.bloomFilterFalsePositiveRate
            )
            
            // Populate bloom filter with all fingerprints
            for fingerprint in fingerprints {
                bloomFilter?.add(fingerprint)
            }
        }
        
        // Find candidate pairs using prefiltering
        for i in 0..<elements.count {
            for j in (i+1)..<elements.count {
                let element1 = elements[i]
                let element2 = elements[j]
                let fingerprint1 = fingerprints[i]
                let fingerprint2 = fingerprints[j]
                
                // Skip comparing elements in the same file with the same name
                if element1.filePath == element2.filePath && element1.name == element2.name {
                    continue
                }
                
                // Early rejection based on candidate pair limit
                if candidates.count >= configuration.maxCandidatePairs {
                    break
                }
                
                // Stage 1: Basic fingerprint similarity check
                guard fingerprint1.mightBeSimilar(
                    to: fingerprint2,
                    sizeRatioThreshold: configuration.sizeRatioThreshold
                ) else {
                    continue
                }
                
                // Stage 2: Bloom filter check (if enabled)
                if let filter = bloomFilter {
                    guard filter.mightBeSimilar(
                        fingerprint1,
                        fingerprint2,
                        threshold: configuration.fingerprintSimilarityThreshold
                    ) else {
                        continue
                    }
                }
                
                // Stage 3: Detailed fingerprint similarity check
                let fingerprintSimilarity = fingerprint1.similarity(to: fingerprint2)
                guard fingerprintSimilarity >= configuration.fingerprintSimilarityThreshold else {
                    continue
                }
                
                // Passed all filters - add as candidate
                candidates.append((i, j))
            }
            
            // Early exit if we've reached the candidate limit
            if candidates.count >= configuration.maxCandidatePairs {
                break
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let prefilteringTime = endTime - startTime
        
        // Collect statistics
        let statistics = PrefilteringStatistics(
            totalPossiblePairs: totalPossiblePairs,
            candidatePairs: candidates.count,
            prefilteringTimeSeconds: prefilteringTime,
            bloomFilterStats: bloomFilter?.getStatistics()
        )
        
        return (candidates, statistics)
    }
    
    /// Finds candidate pairs with priority scoring for most promising candidates
    /// - Parameter elements: Array of code elements to analyze
    /// - Returns: Tuple containing scored candidate pairs and statistics
    public func findScoredCandidatePairs(elements: [CodeElement]) -> (candidates: [(Int, Int, Double)], statistics: PrefilteringStatistics) {
        let (basicCandidates, statistics) = findCandidatePairs(elements: elements)
        
        // Score candidates based on fingerprint similarity
        let fingerprints = elements.map { $0.treeNode.extractFingerprint() }
        var scoredCandidates: [(Int, Int, Double)] = []
        
        for (i, j) in basicCandidates {
            let similarity = fingerprints[i].similarity(to: fingerprints[j])
            scoredCandidates.append((i, j, similarity))
        }
        
        // Sort by similarity score (highest first)
        scoredCandidates.sort { $0.2 > $1.2 }
        
        return (scoredCandidates, statistics)
    }
    
    /// Creates an optimized configuration based on dataset size
    /// - Parameters:
    ///   - elementCount: Number of elements in the dataset
    ///   - targetReduction: Target reduction ratio (default: 0.9)
    /// - Returns: Optimized prefiltering configuration
    public static func optimizedConfiguration(elementCount: Int, targetReduction: Double = 0.9) -> PrefilteringConfiguration {
        var config = PrefilteringConfiguration()
        
        // Adjust thresholds based on dataset size
        if elementCount > 5000 {
            // Large datasets - more aggressive filtering
            config = PrefilteringConfiguration(
                bloomFilterFalsePositiveRate: 0.05,
                fingerprintSimilarityThreshold: 0.4,
                sizeRatioThreshold: 0.4,
                maxCandidatePairs: Int(Double(elementCount * elementCount) * (1.0 - targetReduction)),
                enableBloomFilter: true
            )
        } else if elementCount > 1000 {
            // Medium datasets - balanced filtering
            config = PrefilteringConfiguration(
                bloomFilterFalsePositiveRate: 0.1,
                fingerprintSimilarityThreshold: 0.3,
                sizeRatioThreshold: 0.3,
                maxCandidatePairs: Int(Double(elementCount * elementCount) * (1.0 - targetReduction)),
                enableBloomFilter: true
            )
        } else {
            // Small datasets - minimal filtering
            config = PrefilteringConfiguration(
                bloomFilterFalsePositiveRate: 0.2,
                fingerprintSimilarityThreshold: 0.2,
                sizeRatioThreshold: 0.2,
                maxCandidatePairs: elementCount * elementCount,
                enableBloomFilter: false
            )
        }
        
        return config
    }
}
