import Testing
import Foundation
@testable import swift_similarity

// MARK: - Hash Optimization Tests

@Test("Fast hash values generation")
func testFastHashValuesGeneration() {
    let fingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["FunctionDecl": 2, "Parameter": 4, "CodeBlock": 1],
        totalNodes: 15,
        maxDepth: 4,
        leafNodeCount: 8
    )
    
    let fastHashes = fingerprint.fastHashValues(hashCount: 5)
    let normalHashes = fingerprint.hashValues(hashCount: 5)
    
    // Should generate the same number of hash values
    #expect(fastHashes.count == 5)
    #expect(normalHashes.count == 5)
    
    // Fast and normal should produce identical results (since normal calls fast)
    #expect(fastHashes == normalHashes)
    
    // All hash values should be positive
    for hash in fastHashes {
        #expect(hash >= 0)
    }
}

@Test("Hash value consistency and determinism")
func testHashValueConsistency() {
    let fingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["StructDecl": 1, "Property": 3, "Method": 2],
        totalNodes: 20,
        maxDepth: 5,
        leafNodeCount: 12
    )
    
    // Multiple calls should produce identical results
    let hashes1 = fingerprint.fastHashValues(hashCount: 3)
    let hashes2 = fingerprint.fastHashValues(hashCount: 3)
    let hashes3 = fingerprint.fastHashValues(hashCount: 3)
    
    #expect(hashes1 == hashes2)
    #expect(hashes2 == hashes3)
    
    // Different hash counts should produce arrays with different lengths
    let hashes5 = fingerprint.fastHashValues(hashCount: 5)
    #expect(hashes5.count == 5)
    #expect(hashes1 == Array(hashes5.prefix(3))) // First 3 should be identical (same seeds)
}

@Test("Hash caching functionality")
func testHashCaching() {
    let fingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["ClassDecl": 1, "Method": 5, "Property": 2],
        totalNodes: 25,
        maxDepth: 6,
        leafNodeCount: 15
    )
    
    // Clear cache to start fresh
    ASTNodeFingerprint.clearHashCache()
    
    // First call should calculate and cache
    let cachedHashes1 = fingerprint.cachedHashValues(hashCount: 4)
    
    // Second call should return cached values
    let cachedHashes2 = fingerprint.cachedHashValues(hashCount: 4)
    
    // Should be identical
    #expect(cachedHashes1 == cachedHashes2)
    #expect(cachedHashes1.count == 4)
    
    // Different hash count should calculate new values
    let cachedHashes3 = fingerprint.cachedHashValues(hashCount: 6)
    #expect(cachedHashes3.count == 6)
    
    // Clear cache
    ASTNodeFingerprint.clearHashCache()
}

@Test("Optimized type overlap calculation")
func testOptimizedTypeOverlapCalculation() {
    let fingerprint1 = ASTNodeFingerprint(
        nodeTypeCounts: ["FunctionDecl": 1, "Parameter": 2, "CodeBlock": 1],
        totalNodes: 10,
        maxDepth: 3,
        leafNodeCount: 5
    )
    
    let fingerprint2 = ASTNodeFingerprint(
        nodeTypeCounts: ["FunctionDecl": 1, "Parameter": 3, "ReturnStmt": 1],
        totalNodes: 12,
        maxDepth: 3,
        leafNodeCount: 6
    )
    
    let fingerprint3 = ASTNodeFingerprint(
        nodeTypeCounts: ["ClassDecl": 1, "Method": 5, "Property": 2],
        totalNodes: 30,
        maxDepth: 8,
        leafNodeCount: 20
    )
    
    // Similar fingerprints should pass similarity check
    #expect(fingerprint1.mightBeSimilar(to: fingerprint2, sizeRatioThreshold: 0.3))
    
    // Dissimilar fingerprints should fail similarity check
    #expect(!fingerprint1.mightBeSimilar(to: fingerprint3, sizeRatioThreshold: 0.3))
}

@Test("Hash performance benchmarking")
func testHashPerformanceBenchmarking() {
    let fingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["ComplexNode": 10, "SimpleNode": 20, "ContainerNode": 5],
        totalNodes: 100,
        maxDepth: 10,
        leafNodeCount: 50
    )
    
    let benchmarkResults = fingerprint.benchmarkHashPerformance(iterations: 1000, hashCount: 5)
    
    // Verify benchmark results structure
    #expect(benchmarkResults["total_time_seconds"] as? Double != nil)
    #expect(benchmarkResults["average_time_ms"] as? Double != nil)
    #expect(benchmarkResults["operations_per_second"] as? Double != nil)
    #expect(benchmarkResults["iterations"] as? Int == 1000)
    #expect(benchmarkResults["hash_count"] as? Int == 5)
    
    // Performance should be reasonable
    let avgTimeMs = benchmarkResults["average_time_ms"] as? Double ?? 1000.0
    let opsPerSec = benchmarkResults["operations_per_second"] as? Double ?? 0.0
    
    #expect(avgTimeMs < 1.0) // Should be faster than 1ms per operation
    #expect(opsPerSec > 1000.0) // Should handle more than 1000 operations per second
}

@Test("Hash distribution quality")
func testHashDistributionQuality() {
    let fingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["DistributionTest": 5, "HashQuality": 3, "Performance": 2],
        totalNodes: 50,
        maxDepth: 7,
        leafNodeCount: 25
    )
    
    let distributionResults = fingerprint.testHashDistribution(hashCount: 10, bucketCount: 100)
    
    // Verify distribution results structure
    #expect(distributionResults["non_empty_buckets"] as? Int != nil)
    #expect(distributionResults["max_bucket_count"] as? Int != nil)
    #expect(distributionResults["min_bucket_count"] as? Int != nil)
    #expect(distributionResults["average_bucket_count"] as? Double != nil)
    #expect(distributionResults["distribution_ratio"] as? Double != nil)
    
    // Distribution should be reasonable
    let nonEmptyBuckets = distributionResults["non_empty_buckets"] as? Int ?? 0
    let distributionRatio = distributionResults["distribution_ratio"] as? Double ?? 0.0
    
    #expect(nonEmptyBuckets > 0)
    #expect(distributionRatio > 0.0)
    #expect(distributionRatio <= 1.0)
}

@Test("Hash optimization vs original performance comparison")
func testHashOptimizationPerformance() {
    let complexFingerprint = ASTNodeFingerprint(
        nodeTypeCounts: [
            "FunctionDecl": 10, "StructDecl": 5, "ClassDecl": 3,
            "Parameter": 25, "Property": 15, "Method": 20,
            "CodeBlock": 35, "ReturnStmt": 8, "IfExpr": 12
        ],
        totalNodes: 500,
        maxDepth: 15,
        leafNodeCount: 250
    )
    
    // Benchmark optimized hash calculation
    let optimizedResults = complexFingerprint.benchmarkHashPerformance(iterations: 5000, hashCount: 8)
    let optimizedTime = optimizedResults["total_time_seconds"] as? Double ?? 1.0
    let optimizedOpsPerSec = optimizedResults["operations_per_second"] as? Double ?? 0.0
    
    // Performance should be excellent
    #expect(optimizedTime < 1.0) // Should complete 5000 iterations in under 1 second
    #expect(optimizedOpsPerSec > 5000.0) // Should handle more than 5000 operations per second
    
    // Hash values should still be high quality
    let hashes = complexFingerprint.fastHashValues(hashCount: 8)
    #expect(hashes.count == 8)
    
    // All hashes should be different (very high probability)
    let uniqueHashes = Set(hashes)
    #expect(uniqueHashes.count == 8)
}

@Test("Memory allocation optimization")
func testMemoryAllocationOptimization() {
    let fingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["MemoryTest": 1, "AllocationTest": 2],
        totalNodes: 10,
        maxDepth: 3,
        leafNodeCount: 5
    )
    
    // Multiple calls should not cause memory leaks or excessive allocations
    var allHashes: [[Int]] = []
    
    for i in 1...10 {
        let hashes = fingerprint.fastHashValues(hashCount: i)
        allHashes.append(hashes)
        #expect(hashes.count == i)
    }
    
    // Verify all results are consistent
    for (index, hashes) in allHashes.enumerated() {
        #expect(hashes.count == index + 1)
        for hash in hashes {
            #expect(hash >= 0)
        }
    }
}

@Test("Edge cases and error handling")
func testEdgeCasesAndErrorHandling() {
    // Empty fingerprint
    let emptyFingerprint = ASTNodeFingerprint(
        nodeTypeCounts: [:],
        totalNodes: 0,
        maxDepth: 0,
        leafNodeCount: 0
    )
    
    let emptyHashes = emptyFingerprint.fastHashValues(hashCount: 3)
    #expect(emptyHashes.count == 3)
    
    // Zero hash count
    let zeroHashes = emptyFingerprint.fastHashValues(hashCount: 0)
    #expect(zeroHashes.isEmpty)
    
    // Large hash count
    let largeHashes = emptyFingerprint.fastHashValues(hashCount: 100)
    #expect(largeHashes.count == 100)
    
    // Single element fingerprint
    let singleFingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["SingleNode": 1],
        totalNodes: 1,
        maxDepth: 1,
        leafNodeCount: 1
    )
    
    let singleHashes = singleFingerprint.fastHashValues(hashCount: 5)
    #expect(singleHashes.count == 5)
    
    // Similarity check with empty fingerprints should fail due to size ratio
    #expect(!emptyFingerprint.mightBeSimilar(to: singleFingerprint, sizeRatioThreshold: 0.1))
} 