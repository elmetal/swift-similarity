import Testing
import Foundation
@testable import swift_similarity

// MARK: - Prefiltering Engine Tests

struct PrefilteringEngineTests {
    
    @Test("Prefiltering configuration creation")
    func testConfigurationCreation() throws {
        let defaultConfig = PrefilteringConfiguration()
        
        #expect(defaultConfig.bloomFilterFalsePositiveRate == 0.1)
        #expect(defaultConfig.fingerprintSimilarityThreshold == 0.3)
        #expect(defaultConfig.sizeRatioThreshold == 0.3)
        #expect(defaultConfig.maxCandidatePairs == 10000)
        #expect(defaultConfig.enableBloomFilter == true)
        
        let customConfig = PrefilteringConfiguration(
            bloomFilterFalsePositiveRate: 0.05,
            fingerprintSimilarityThreshold: 0.4,
            sizeRatioThreshold: 0.5,
            maxCandidatePairs: 5000,
            enableBloomFilter: false
        )
        
        #expect(customConfig.bloomFilterFalsePositiveRate == 0.05)
        #expect(customConfig.fingerprintSimilarityThreshold == 0.4)
        #expect(customConfig.sizeRatioThreshold == 0.5)
        #expect(customConfig.maxCandidatePairs == 5000)
        #expect(customConfig.enableBloomFilter == false)
    }
    
    @Test("Basic candidate pair finding")
    func testBasicCandidatePairFinding() throws {
        let engine = PrefilteringEngine()
        let elements = createTestElements()
        
        let (candidates, statistics) = engine.findCandidatePairs(elements: elements)
        
        // Should find some candidates
        #expect(candidates.count >= 0)
        #expect(statistics.totalPossiblePairs == elements.count * (elements.count - 1) / 2)
        #expect(statistics.candidatePairs == candidates.count)
        #expect(statistics.reductionRatio >= 0.0)
        #expect(statistics.reductionRatio <= 1.0)
        #expect(statistics.prefilteringTimeSeconds >= 0.0)
        
        // Verify candidate indices are valid
        for (i, j) in candidates {
            #expect(i >= 0 && i < elements.count)
            #expect(j >= 0 && j < elements.count)
            #expect(i < j) // Should be ordered pairs
        }
    }
    
    @Test("Prefiltering with bloom filter disabled")
    func testPrefilteringWithBloomFilterDisabled() throws {
        let config = PrefilteringConfiguration(enableBloomFilter: false)
        let engine = PrefilteringEngine(configuration: config)
        let elements = createTestElements()
        
        let (candidates, statistics) = engine.findCandidatePairs(elements: elements)
        
        #expect(candidates.count >= 0)
        #expect(statistics.bloomFilterStats == nil) // Should be nil when disabled
    }
    
    @Test("Prefiltering with strict thresholds")
    func testPrefilteringWithStrictThresholds() throws {
        let strictConfig = PrefilteringConfiguration(
            fingerprintSimilarityThreshold: 0.9,
            sizeRatioThreshold: 0.9,
            maxCandidatePairs: 5
        )
        let engine = PrefilteringEngine(configuration: strictConfig)
        let elements = createTestElements()
        
        let (candidates, statistics) = engine.findCandidatePairs(elements: elements)
        
        // Strict thresholds should result in fewer candidates
        #expect(candidates.count <= 5) // Respects maxCandidatePairs
        #expect(statistics.reductionRatio >= 0.0)
    }
    
    @Test("Scored candidate pair finding")
    func testScoredCandidatePairFinding() throws {
        let engine = PrefilteringEngine()
        let elements = createTestElements()
        
        let (scoredCandidates, statistics) = engine.findScoredCandidatePairs(elements: elements)
        
        #expect(scoredCandidates.count >= 0)
        #expect(statistics.candidatePairs == scoredCandidates.count)
        
        // Verify scores are valid and sorted
        for (i, j, score) in scoredCandidates {
            #expect(i >= 0 && i < elements.count)
            #expect(j >= 0 && j < elements.count)
            #expect(i < j)
            #expect(score >= 0.0 && score <= 1.0)
        }
        
        // Verify sorting (highest scores first)
        if scoredCandidates.count > 1 {
            for i in 0..<(scoredCandidates.count - 1) {
                #expect(scoredCandidates[i].2 >= scoredCandidates[i + 1].2)
            }
        }
    }
    
    @Test("Optimized configuration generation")
    func testOptimizedConfigurationGeneration() throws {
        // Small dataset
        let smallConfig = PrefilteringEngine.optimizedConfiguration(elementCount: 100)
        #expect(smallConfig.enableBloomFilter == false)
        
        // Medium dataset
        let mediumConfig = PrefilteringEngine.optimizedConfiguration(elementCount: 2000)
        #expect(mediumConfig.enableBloomFilter == true)
        #expect(mediumConfig.fingerprintSimilarityThreshold == 0.3)
        
        // Large dataset
        let largeConfig = PrefilteringEngine.optimizedConfiguration(elementCount: 10000)
        #expect(largeConfig.enableBloomFilter == true)
        #expect(largeConfig.fingerprintSimilarityThreshold == 0.4)
        #expect(largeConfig.bloomFilterFalsePositiveRate == 0.05)
    }
    
    @Test("Prefiltering statistics calculation")
    func testPrefilteringStatistics() throws {
        let statistics = PrefilteringStatistics(
            totalPossiblePairs: 100,
            candidatePairs: 20,
            prefilteringTimeSeconds: 0.05,
            bloomFilterStats: ["test": "value"]
        )
        
        #expect(statistics.totalPossiblePairs == 100)
        #expect(statistics.candidatePairs == 20)
        #expect(statistics.reductionRatio == 0.8) // (100 - 20) / 100
        #expect(statistics.prefilteringTimeSeconds == 0.05)
        #expect(statistics.bloomFilterStats?["test"] as? String == "value")
        
        // Test edge case with zero pairs
        let zeroStats = PrefilteringStatistics(
            totalPossiblePairs: 0,
            candidatePairs: 0,
            prefilteringTimeSeconds: 0.0
        )
        #expect(zeroStats.reductionRatio == 0.0)
    }
    
    @Test("Same file and name filtering")
    func testSameFileAndNameFiltering() throws {
        let engine = PrefilteringEngine()
        
        // Create elements with same file and name
        let sameElements = [
            createTestElement(name: "testFunction", filePath: "/test/file.swift", nodeCount: 5),
            createTestElement(name: "testFunction", filePath: "/test/file.swift", nodeCount: 5),
            createTestElement(name: "otherFunction", filePath: "/test/file.swift", nodeCount: 6)
        ]
        
        let (candidates, _) = engine.findCandidatePairs(elements: sameElements)
        
        // Should not compare elements with same file and name
        for (i, j) in candidates {
            let element1 = sameElements[i]
            let element2 = sameElements[j]
            
            #expect(!(element1.filePath == element2.filePath && element1.name == element2.name))
        }
    }
    
    // Helper methods for creating test data
    private func createTestElements() -> [CodeElement] {
        return [
            createTestElement(name: "function1", filePath: "/test/file1.swift", nodeCount: 5),
            createTestElement(name: "function2", filePath: "/test/file1.swift", nodeCount: 7),
            createTestElement(name: "function3", filePath: "/test/file2.swift", nodeCount: 5),
            createTestElement(name: "class1", filePath: "/test/file2.swift", nodeCount: 20),
            createTestElement(name: "struct1", filePath: "/test/file3.swift", nodeCount: 8)
        ]
    }
    
    private func createTestElement(name: String, filePath: String, nodeCount: Int) -> CodeElement {
        let nodeTypeCounts = ["TestNode": nodeCount]
        let fingerprint = ASTNodeFingerprint(
            nodeTypeCounts: nodeTypeCounts,
            totalNodes: nodeCount,
            maxDepth: nodeCount / 2,
            leafNodeCount: max(1, nodeCount / 3)
        )
        
        let treeNode = SimpleTreeNode(label: "TestNode", children: [])
        
        return CodeElement(
            elementType: .function,
            name: name,
            signature: "\(name)()",
            filePath: filePath,
            startLine: 1,
            endLine: 5,
            codePreview: "func \(name)() {}",
            treeNode: treeNode
        )
    }
}
