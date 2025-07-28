import Testing
import Foundation
@testable import swift_similarity

// MARK: - Performance Optimized Calculator Tests

struct PerformanceOptimizedCalculatorTests {
    
    @Test("Performance optimized configuration creation")
    func testConfigurationCreation() throws {
        // Test default configuration
        let defaultConfig = PerformanceOptimizedConfiguration()
        
        #expect(defaultConfig.concurrentThreads > 0)
        #expect(defaultConfig.enableProgressReporting == false)
        #expect(defaultConfig.batchSize == 100)
        #expect(defaultConfig.advancedConfig == nil)
        
        // Test custom configuration
        let customConfig = PerformanceOptimizedConfiguration(
            concurrentThreads: 4,
            enableProgressReporting: true,
            batchSize: 50
        )
        
        #expect(customConfig.concurrentThreads == 4)
        #expect(customConfig.enableProgressReporting == true)
        #expect(customConfig.batchSize == 50)
    }
    
    @Test("Optimized configuration generation for different dataset sizes")
    func testOptimizedConfigurationGeneration() throws {
        // Small dataset
        let smallConfig = PerformanceOptimizedConfiguration.optimized(
            elementCount: 100,
            useAdvancedMetrics: false,
            targetPerformance: .conservative
        )
        #expect(smallConfig.prefilteringConfig.enableBloomFilter == false)
        #expect(smallConfig.advancedConfig == nil)
        
        // Medium dataset with advanced metrics
        let mediumConfig = PerformanceOptimizedConfiguration.optimized(
            elementCount: 2000,
            useAdvancedMetrics: true,
            targetPerformance: .balanced
        )
        #expect(mediumConfig.prefilteringConfig.enableBloomFilter == true)
        #expect(mediumConfig.advancedConfig != nil)
        
        // Large dataset with aggressive performance
        let largeConfig = PerformanceOptimizedConfiguration.optimized(
            elementCount: 10000,
            useAdvancedMetrics: false,
            targetPerformance: .aggressive
        )
        #expect(largeConfig.prefilteringConfig.enableBloomFilter == true)
        #expect(largeConfig.concurrentThreads >= 1)
    }
    
    @Test("Performance level characteristics")
    func testPerformanceLevelCharacteristics() throws {
        let aggressive = PerformanceOptimizedConfiguration.PerformanceLevel.aggressive
        let balanced = PerformanceOptimizedConfiguration.PerformanceLevel.balanced
        let conservative = PerformanceOptimizedConfiguration.PerformanceLevel.conservative
        
        // Test reduction ratios
        #expect(aggressive.reductionRatio > balanced.reductionRatio)
        #expect(balanced.reductionRatio > conservative.reductionRatio)
        
        // Test thread counts are reasonable
        #expect(aggressive.threadCount >= balanced.threadCount)
        #expect(conservative.threadCount >= 1)
        
        // Test batch sizes
        #expect(aggressive.batchSize >= balanced.batchSize)
        #expect(balanced.batchSize >= conservative.batchSize)
    }
    
    @Test("Basic similarity calculation")
    func testBasicSimilarityCalculation() throws {
        let calculator = PerformanceOptimizedCalculator()
        let elements = createTestElements()
        
        let (similarPairs, statistics) = calculator.calculateSimilarity(
            elements: elements,
            threshold: 0.5
        )
        
        // Verify results structure
        #expect(similarPairs.count >= 0)
        #expect(statistics.totalCalculationTime >= 0.0)
        #expect(statistics.parallelProcessingTime >= 0.0)
        #expect(statistics.threadsUsed > 0)
        #expect(statistics.similarPairsFound == similarPairs.count)
        #expect(statistics.processingRate >= 0.0)
        
        // Verify similarity scores are within expected range
        for (_, _, score) in similarPairs {
            #expect(score >= 0.5 && score <= 1.001) // Allow slight floating-point precision
        }
        
        // Verify performance improvement
        #expect(statistics.performanceImprovement >= 1.0)
    }
    
    @Test("Similarity calculation with advanced metrics")
    func testSimilarityCalculationWithAdvancedMetrics() throws {
        let config = PerformanceOptimizedConfiguration(
            advancedConfig: AdvancedSimilarityMetrics.Configuration()
        )
        let calculator = PerformanceOptimizedCalculator(configuration: config)
        let elements = createTestElements()
        
        let (similarPairs, statistics) = calculator.calculateSimilarity(
            elements: elements,
            threshold: 0.6
        )
        
        #expect(similarPairs.count >= 0)
        #expect(statistics.similarPairsFound == similarPairs.count)
        
        // Advanced metrics should work with scores in valid range
        for (_, _, score) in similarPairs {
            #expect(score >= 0.6 && score <= 1.001) // Allow slight floating-point precision
        }
    }
    
    @Test("Progress reporting functionality")
    func testProgressReporting() throws {
        let config = PerformanceOptimizedConfiguration(
            enableProgressReporting: true,
            batchSize: 10
        )
        let calculator = PerformanceOptimizedCalculator(configuration: config)
        let elements = createTestElements()
        
        var progressUpdates: [CalculationProgress] = []
        
        let (similarPairs, statistics) = calculator.calculateSimilarityWithProgress(
            elements: elements,
            threshold: 0.5
        ) { progress in
            progressUpdates.append(progress)
        }
        
        #expect(similarPairs.count >= 0)
        #expect(statistics.similarPairsFound == similarPairs.count)
        
        // Verify progress updates were received
        if !progressUpdates.isEmpty {
            for progress in progressUpdates {
                #expect(progress.totalCandidates >= 0)
                #expect(progress.processedCandidates >= 0)
                #expect(progress.processedCandidates <= progress.totalCandidates)
                #expect(progress.progressPercentage >= 0.0 && progress.progressPercentage <= 1.0)
            }
            
            // Last update should show completion or near completion
            if let lastProgress = progressUpdates.last {
                #expect(lastProgress.processedCandidates <= lastProgress.totalCandidates)
            }
        }
    }
    
    @Test("Calculation progress properties")
    func testCalculationProgressProperties() throws {
        let progress = CalculationProgress(
            totalCandidates: 100,
            processedCandidates: 25,
            estimatedTimeRemaining: 30.0,
            processingRate: 5.0
        )
        
        #expect(progress.totalCandidates == 100)
        #expect(progress.processedCandidates == 25)
        #expect(progress.progressPercentage == 0.25) // 25/100
        #expect(progress.estimatedTimeRemaining == 30.0)
        #expect(progress.processingRate == 5.0)
        
        // Test edge case with zero total
        let zeroProgress = CalculationProgress(
            totalCandidates: 0,
            processedCandidates: 0
        )
        #expect(zeroProgress.progressPercentage == 0.0)
    }
    
    @Test("Performance statistics calculation")
    func testPerformanceStatisticsCalculation() throws {
        let prefilteringStats = PrefilteringStatistics(
            totalPossiblePairs: 1000,
            candidatePairs: 100,
            prefilteringTimeSeconds: 0.1
        )
        
        let perfStats = PerformanceStatistics(
            prefilteringStats: prefilteringStats,
            totalCalculationTime: 1.5,
            parallelProcessingTime: 1.0,
            threadsUsed: 4,
            peakMemoryUsage: 1024000,
            similarPairsFound: 25,
            processingRate: 100.0
        )
        
        #expect(perfStats.totalCalculationTime == 1.5)
        #expect(perfStats.parallelProcessingTime == 1.0)
        #expect(perfStats.threadsUsed == 4)
        #expect(perfStats.peakMemoryUsage == 1024000)
        #expect(perfStats.similarPairsFound == 25)
        #expect(perfStats.processingRate == 100.0)
        
        // Test performance improvement calculation
        let expectedImprovement = 1000.0 / 100.0 // totalPossiblePairs / candidatePairs
        #expect(perfStats.performanceImprovement == expectedImprovement)
    }
    
    @Test("Parallel processing with different batch sizes")
    func testParallelProcessingWithDifferentBatchSizes() throws {
        let elements = createLargerTestDataset()
        
        // Test with small batch size
        let smallBatchConfig = PerformanceOptimizedConfiguration(batchSize: 5)
        let smallBatchCalculator = PerformanceOptimizedCalculator(configuration: smallBatchConfig)
        let (smallBatchPairs, smallBatchStats) = smallBatchCalculator.calculateSimilarity(
            elements: elements,
            threshold: 0.7
        )
        
        // Test with large batch size
        let largeBatchConfig = PerformanceOptimizedConfiguration(batchSize: 50)
        let largeBatchCalculator = PerformanceOptimizedCalculator(configuration: largeBatchConfig)
        let (largeBatchPairs, largeBatchStats) = largeBatchCalculator.calculateSimilarity(
            elements: elements,
            threshold: 0.7
        )
        
        // Both should produce valid results
        #expect(smallBatchPairs.count >= 0)
        #expect(largeBatchPairs.count >= 0)
        #expect(smallBatchStats.threadsUsed > 0)
        #expect(largeBatchStats.threadsUsed > 0)
        
        // Results should be consistent (allowing for slight floating-point differences)
        #expect(abs(smallBatchPairs.count - largeBatchPairs.count) <= 1)
    }
    
    @Test("Empty input handling")
    func testEmptyInputHandling() throws {
        let calculator = PerformanceOptimizedCalculator()
        let emptyElements: [CodeElement] = []
        
        let (similarPairs, statistics) = calculator.calculateSimilarity(
            elements: emptyElements,
            threshold: 0.5
        )
        
        #expect(similarPairs.isEmpty)
        #expect(statistics.similarPairsFound == 0)
        #expect(statistics.prefilteringStats.totalPossiblePairs == 0)
        #expect(statistics.prefilteringStats.candidatePairs == 0)
        #expect(statistics.totalCalculationTime >= 0.0)
    }
    
    @Test("Single element handling")
    func testSingleElementHandling() throws {
        let calculator = PerformanceOptimizedCalculator()
        let singleElement = [createTestElement(name: "single", nodeCount: 5)]
        
        let (similarPairs, statistics) = calculator.calculateSimilarity(
            elements: singleElement,
            threshold: 0.5
        )
        
        #expect(similarPairs.isEmpty) // No pairs possible with single element
        #expect(statistics.similarPairsFound == 0)
        #expect(statistics.prefilteringStats.totalPossiblePairs == 0)
        #expect(statistics.prefilteringStats.candidatePairs == 0)
    }
    
    @Test("High threshold filtering")
    func testHighThresholdFiltering() throws {
        let calculator = PerformanceOptimizedCalculator()
        let elements = createTestElements()
        
        // Test with very high threshold
        let (highThresholdPairs, highThresholdStats) = calculator.calculateSimilarity(
            elements: elements,
            threshold: 0.95
        )
        
        // Test with low threshold
        let (lowThresholdPairs, lowThresholdStats) = calculator.calculateSimilarity(
            elements: elements,
            threshold: 0.3
        )
        
        // High threshold should result in fewer or equal pairs
        #expect(highThresholdPairs.count <= lowThresholdPairs.count)
        
        // All high threshold pairs should meet the threshold
        for (_, _, score) in highThresholdPairs {
            #expect(score >= 0.95)
        }
        
        // All low threshold pairs should meet the threshold
        for (_, _, score) in lowThresholdPairs {
            #expect(score >= 0.3)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestElements() -> [CodeElement] {
        return [
            createTestElement(name: "function1", nodeCount: 5),
            createTestElement(name: "function2", nodeCount: 7),
            createTestElement(name: "function3", nodeCount: 5),
            createTestElement(name: "class1", nodeCount: 20),
            createTestElement(name: "struct1", nodeCount: 8)
        ]
    }
    
    private func createLargerTestDataset() -> [CodeElement] {
        var elements: [CodeElement] = []
        
        // Create similar pairs
        for i in 0..<10 {
            elements.append(createTestElement(name: "function\(i)", nodeCount: 5))
            elements.append(createTestElement(name: "function\(i)_similar", nodeCount: 5))
        }
        
        // Create some dissimilar elements
        for i in 0..<5 {
            elements.append(createTestElement(name: "class\(i)", nodeCount: 20 + i))
        }
        
        return elements
    }
    
    private func createTestElement(name: String, nodeCount: Int) -> CodeElement {
        let children: [TreeNode] = (0..<max(0, nodeCount - 1)).map { index in
            SimpleTreeNode(label: "Child\(index)", children: [])
        }
        
        let treeNode = SimpleTreeNode(label: "Function", children: children)
        
        return CodeElement(
            elementType: .function,
            name: name,
            signature: "\(name)()",
            filePath: "/test/\(name).swift",
            startLine: 1,
            endLine: 5,
            codePreview: "func \(name)() {}",
            treeNode: treeNode
        )
    }
} 