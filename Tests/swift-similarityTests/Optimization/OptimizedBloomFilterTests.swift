import Testing
import Foundation
@testable import swift_similarity

// MARK: - Optimized Bloom Filter Tests

@Test("OptimizedBloomFilter creation with default parameters")
func testOptimizedBloomFilterCreation() {
    let filter = OptimizedBloomFilter(expectedElements: 100)
    let stats = filter.getStatistics()
    
    #expect(stats["expected_elements"] as? Int == 100)
    #expect(stats["target_false_positive_rate"] as? Double == 0.1)
    #expect(stats["hash_functions"] as? Int ?? 0 > 0)
    #expect(stats["size"] as? Int ?? 0 > 0)
    #expect(stats["word_count"] as? Int ?? 0 > 0)
}

@Test("OptimizedBloomFilter insertion and lookup")
func testOptimizedBloomFilterInsertionAndLookup() {
    var filter = OptimizedBloomFilter.forTesting()
    
    // Create test fingerprint
    let fingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["TestNode": 1],
        totalNodes: 1,
        maxDepth: 1,
        leafNodeCount: 1
    )
    
    // Initially should not contain the fingerprint
    #expect(!filter.contains(fingerprint))
    
    // Add fingerprint
    filter.add(fingerprint)
    
    // Should now contain the fingerprint
    #expect(filter.contains(fingerprint))
}

@Test("OptimizedBloomFilter memory usage optimization")
func testMemoryUsageOptimization() {
    let filter = OptimizedBloomFilter(expectedElements: 1000, falsePositiveRate: 0.1)
    
    let actualMemoryUsage = filter.memoryUsage
    let boolArrayMemoryUsage = filter.memoryUsageIfBoolArray
    let reductionFactor = filter.memoryReductionFactor
    
    // Should use significantly less memory than Bool array
    #expect(actualMemoryUsage < boolArrayMemoryUsage)
    #expect(reductionFactor > 4.0) // Should be close to 8x reduction
    
    let stats = filter.getStatistics()
    #expect(stats["memory_usage_bytes"] as? Int == actualMemoryUsage)
    #expect(stats["memory_reduction_factor"] as? Double ?? 0.0 > 4.0)
}

@Test("OptimizedBloomFilter with different fingerprints")
func testOptimizedBloomFilterWithDifferentFingerprints() {
    var filter = OptimizedBloomFilter.forTesting()
    
    let fingerprint1 = ASTNodeFingerprint(
        nodeTypeCounts: ["FunctionDecl": 1, "Parameter": 2],
        totalNodes: 5,
        maxDepth: 3,
        leafNodeCount: 2
    )
    
    let fingerprint2 = ASTNodeFingerprint(
        nodeTypeCounts: ["StructDecl": 1, "Property": 3],
        totalNodes: 8,
        maxDepth: 2,
        leafNodeCount: 3
    )
    
    // Add first fingerprint
    filter.add(fingerprint1)
    #expect(filter.contains(fingerprint1))
    
    // Second fingerprint should not be contained initially
    let _ = filter.contains(fingerprint2)
    // Note: This might be true due to false positives, which is expected behavior
    
    // Add second fingerprint
    filter.add(fingerprint2)
    #expect(filter.contains(fingerprint1))
    #expect(filter.contains(fingerprint2))
}

@Test("OptimizedBloomFilter similarity check")
func testOptimizedBloomFilterSimilarityCheck() {
    let filter = OptimizedBloomFilter(expectedElements: 100, falsePositiveRate: 0.1)
    
    // Very similar fingerprints (almost identical)
    let similarFingerprint1 = ASTNodeFingerprint(
        nodeTypeCounts: ["FunctionDecl": 1, "Parameter": 2, "CodeBlock": 1],
        totalNodes: 8,
        maxDepth: 3,
        leafNodeCount: 4
    )
    
    let similarFingerprint2 = ASTNodeFingerprint(
        nodeTypeCounts: ["FunctionDecl": 1, "Parameter": 2, "CodeBlock": 1],
        totalNodes: 8,
        maxDepth: 3,
        leafNodeCount: 4
    )
    
    // Very different fingerprints
    let dissimilarFingerprint = ASTNodeFingerprint(
        nodeTypeCounts: ["ClassDecl": 5, "Method": 20, "Property": 15],
        totalNodes: 150,
        maxDepth: 15,
        leafNodeCount: 80
    )
    
    // Identical fingerprints should pass similarity check
    #expect(filter.mightBeSimilar(similarFingerprint1, similarFingerprint2, threshold: 0.8))
    
    // Very dissimilar fingerprints should fail similarity check
    #expect(!filter.mightBeSimilar(similarFingerprint1, dissimilarFingerprint, threshold: 0.5))
}

@Test("OptimizedBloomFilter statistics tracking")
func testOptimizedBloomFilterStatistics() {
    var filter = OptimizedBloomFilter(expectedElements: 50, falsePositiveRate: 0.05)
    let initialStats = filter.getStatistics()
    
    #expect(initialStats["set_bits"] as? Int == 0)
    #expect(initialStats["load_factor"] as? Double == 0.0)
    
    // Add some fingerprints
    for i in 0..<10 {
        let fingerprint = ASTNodeFingerprint(
            nodeTypeCounts: ["TestNode\(i)": 1],
            totalNodes: i + 1,
            maxDepth: 2,
            leafNodeCount: 1
        )
        filter.add(fingerprint)
    }
    
    let finalStats = filter.getStatistics()
    let setBits = finalStats["set_bits"] as? Int ?? 0
    let loadFactor = finalStats["load_factor"] as? Double ?? 0.0
    
    #expect(setBits > 0)
    #expect(loadFactor > 0.0)
    #expect(loadFactor <= 1.0)
    
    // Verify target false positive rate is stored correctly
    let targetRate = finalStats["target_false_positive_rate"] as? Double ?? 1.0
    #expect(abs(targetRate - 0.05) < 0.001)
}

@Test("OptimizedBloomFilter for AST fingerprints factory")
func testOptimizedBloomFilterForASTFingerprints() {
    let filter = OptimizedBloomFilter.forASTFingerprints(elementCount: 100, targetAccuracy: 0.95)
    let stats = filter.getStatistics()
    
    let expectedElements = stats["expected_elements"] as? Int ?? 0
    let targetRate = stats["target_false_positive_rate"] as? Double ?? 1.0
    
    // Should create filter for pairwise comparisons
    #expect(expectedElements > 100) // Should be elementCount * (elementCount - 1) / 2
    #expect(abs(targetRate - 0.05) < 0.001) // 1.0 - 0.95 = 0.05
}

// Note: Backward compatibility test removed as BloomFilter.swift has been deleted
// @Test("OptimizedBloomFilter backward compatibility")
// func testOptimizedBloomFilterBackwardCompatibility() {
//     // This test is commented out because BloomFilter and from() method have been removed
// }

@Test("OptimizedBloomFilter bit operations performance")
func testBitOperationsPerformance() {
    var filter = OptimizedBloomFilter(expectedElements: 10000, falsePositiveRate: 0.01)
    
    // Create many fingerprints for performance testing
    var fingerprints: [ASTNodeFingerprint] = []
    for i in 0..<1000 {
        let fingerprint = ASTNodeFingerprint(
            nodeTypeCounts: ["Node\(i % 10)": i % 5 + 1],
            totalNodes: i % 20 + 5,
            maxDepth: i % 8 + 2,
            leafNodeCount: i % 10 + 1
        )
        fingerprints.append(fingerprint)
    }
    
    // Measure insertion performance
    let startTime = ProcessInfo.processInfo.systemUptime
    
    for fingerprint in fingerprints {
        filter.add(fingerprint)
    }
    
    let insertionTime = ProcessInfo.processInfo.systemUptime - startTime
    
    // Measure lookup performance
    let lookupStartTime = ProcessInfo.processInfo.systemUptime
    
    var containsCount = 0
    for fingerprint in fingerprints {
        if filter.contains(fingerprint) {
            containsCount += 1
        }
    }
    
    let lookupTime = ProcessInfo.processInfo.systemUptime - lookupStartTime
    
    // All fingerprints should be found (no false negatives)
    #expect(containsCount == fingerprints.count)
    
    // Performance should be reasonable (these are loose bounds for CI)
    #expect(insertionTime < 1.0) // Should insert 1000 items in under 1 second
    #expect(lookupTime < 1.0) // Should lookup 1000 items in under 1 second
    
    // Memory usage should be significantly lower than Bool array
    #expect(filter.memoryReductionFactor > 4.0)
}

@Test("OptimizedBloomFilter large dataset handling")
func testLargeDatasetHandling() {
    let filter = OptimizedBloomFilter(expectedElements: 100000, falsePositiveRate: 0.01)
    let stats = filter.getStatistics()
    
    let size = stats["size"] as? Int ?? 0
    let wordCount = stats["word_count"] as? Int ?? 0
    let memoryUsage = stats["memory_usage_bytes"] as? Int ?? 0
    
    // Verify proper scaling for large datasets
    #expect(size > 500000) // Should be large enough for low false positive rate
    #expect(wordCount == (size + 63) / 64) // Correct word count calculation
    #expect(memoryUsage == wordCount * 8) // Correct memory usage calculation
    
    // Memory should still be reasonable
    #expect(memoryUsage < 10_000_000) // Less than 10MB for 100K elements
} 