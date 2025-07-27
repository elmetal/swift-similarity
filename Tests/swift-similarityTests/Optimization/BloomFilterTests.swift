import Testing
import Foundation
@testable import swift_similarity

// MARK: - Bloom Filter Tests

struct BloomFilterTests {
    
    @Test("Bloom filter creation with default parameters")
    func testBloomFilterCreation() throws {
        let filter = BloomFilter(expectedElements: 100, falsePositiveRate: 0.1)
        let stats = filter.getStatistics()
        
        #expect(stats["expected_elements"] as? Int == 100)
        #expect(stats["target_false_positive_rate"] as? Double == 0.1)
        #expect(stats["size"] as? Int ?? 0 > 0)
        #expect(stats["hash_functions"] as? Int ?? 0 > 0)
        #expect(stats["set_bits"] as? Int == 0) // Should start empty
        #expect(stats["load_factor"] as? Double == 0.0)
    }
    
    @Test("Bloom filter insertion and lookup")
    func testInsertionAndLookup() throws {
        var filter = BloomFilter.forTesting()
        
        // Create test fingerprints
        let fingerprint1 = createTestFingerprint(label: "TestFunction1", nodeCount: 5)
        let fingerprint2 = createTestFingerprint(label: "TestFunction2", nodeCount: 8)
        
        // Initially should not contain any fingerprints
        #expect(filter.contains(fingerprint1) == false)
        #expect(filter.contains(fingerprint2) == false)
        
        // Add first fingerprint
        filter.add(fingerprint1)
        #expect(filter.contains(fingerprint1) == true)
        #expect(filter.contains(fingerprint2) == false) // Should still be false (unless hash collision)
        
        // Add second fingerprint
        filter.add(fingerprint2)
        #expect(filter.contains(fingerprint1) == true)
        #expect(filter.contains(fingerprint2) == true)
    }
    
    @Test("Bloom filter similarity check")
    func testSimilarityCheck() throws {
        let filter = BloomFilter.forTesting()
        
        // Create similar fingerprints (same size, similar structure)
        let fp1 = createTestFingerprint(label: "Function", nodeCount: 5)
        let fp2 = createTestFingerprint(label: "Function", nodeCount: 5)
        
        // Create dissimilar fingerprints (very different sizes)
        let fp3 = createTestFingerprint(label: "LargeClass", nodeCount: 50)
        
        // Similar fingerprints should pass similarity check
        #expect(filter.mightBeSimilar(fp1, fp2, threshold: 0.3) == true)
        
        // Very dissimilar fingerprints should fail similarity check
        #expect(filter.mightBeSimilar(fp1, fp3, threshold: 0.3) == false)
    }
    
    @Test("Bloom filter for AST fingerprints factory")
    func testASTFingerprintsFactory() throws {
        let filter = BloomFilter.forASTFingerprints(elementCount: 100, targetAccuracy: 0.95)
        let stats = filter.getStatistics()
        
        let targetRate = stats["target_false_positive_rate"] as? Double ?? 0.0
        #expect(abs(targetRate - 0.05) < 0.001) // Allow for floating point precision
        #expect(stats["size"] as? Int ?? 0 > 0)
        #expect(stats["hash_functions"] as? Int ?? 0 > 0)
    }
    
    @Test("Bloom filter statistics tracking")
    func testStatisticsTracking() throws {
        var filter = BloomFilter.forTesting()
        let initialStats = filter.getStatistics()
        
        // Initially no bits should be set
        #expect(initialStats["set_bits"] as? Int == 0)
        #expect(initialStats["load_factor"] as? Double == 0.0)
        
        // Add some fingerprints
        let fp1 = createTestFingerprint(label: "Test1", nodeCount: 3)
        let fp2 = createTestFingerprint(label: "Test2", nodeCount: 4)
        
        filter.add(fp1)
        filter.add(fp2)
        
        let afterStats = filter.getStatistics()
        
        // Some bits should now be set
        #expect((afterStats["set_bits"] as? Int ?? 0) > 0)
        #expect((afterStats["load_factor"] as? Double ?? 0.0) > 0.0)
    }
    
    @Test("Bloom filter with different fingerprints")
    func testDifferentFingerprints() throws {
        var filter = BloomFilter.forTesting()
        
        // Create fingerprints with different characteristics
        let functionFp = createTestFingerprint(label: "FunctionDecl", nodeCount: 5)
        let classFp = createTestFingerprint(label: "ClassDecl", nodeCount: 15)
        let structFp = createTestFingerprint(label: "StructDecl", nodeCount: 8)
        
        // Add all fingerprints
        filter.add(functionFp)
        filter.add(classFp)
        filter.add(structFp)
        
        // All should be found
        #expect(filter.contains(functionFp) == true)
        #expect(filter.contains(classFp) == true)
        #expect(filter.contains(structFp) == true)
        
        // Create a new fingerprint that wasn't added
        let newFp = createTestFingerprint(label: "EnumDecl", nodeCount: 6)
        
        // This might return true (false positive) or false (correct negative)
        // We can't assert the exact result, but can verify the method doesn't crash
        let result = filter.contains(newFp)
        #expect(result == true || result == false) // Should be boolean
    }
    
    // Helper method to create test fingerprints
    private func createTestFingerprint(label: String, nodeCount: Int) -> ASTNodeFingerprint {
        let nodeTypeCounts = [label: nodeCount]
        return ASTNodeFingerprint(
            nodeTypeCounts: nodeTypeCounts,
            totalNodes: nodeCount,
            maxDepth: nodeCount / 2,
            leafNodeCount: max(1, nodeCount / 3)
        )
    }
}
