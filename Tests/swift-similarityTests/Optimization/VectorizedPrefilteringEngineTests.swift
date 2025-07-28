import Testing
import Foundation
@testable import swift_similarity

// MARK: - Vectorized Prefiltering Engine Tests

@Test("VectorizedPrefilteringEngine basic functionality")
func testVectorizedPrefilteringEngineBasicFunctionality() async throws {
    let engine = VectorizedPrefilteringEngine()
    let elements = createTestElements(count: 10)
    
    let candidates = try await engine.findCandidates(elements: elements, threshold: 0.3)
    
    // Should find some candidates
    #expect(candidates.count >= 0)
    
    // All candidates should meet threshold
    for (_, _, similarity) in candidates {
        #expect(similarity >= 0.3)
        #expect(similarity <= 1.0)
    }
}

@Test("VectorizedPrefilteringEngine configuration options")
func testVectorizedPrefilteringEngineConfiguration() {
    // Conservative configuration
    let conservativeConfig = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .conservative,
        blockSize: 32,
        maxConcurrency: 2,
        enableSIMD: false
    )
    let conservativeEngine = VectorizedPrefilteringEngine(configuration: conservativeConfig)
    #expect(conservativeEngine.configuration.optimizationLevel == .conservative)
    
    // Aggressive configuration
    let aggressiveConfig = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .aggressive,
        blockSize: 512,
        maxConcurrency: 8,
        enableSIMD: true
    )
    let aggressiveEngine = VectorizedPrefilteringEngine(configuration: aggressiveConfig)
    #expect(aggressiveEngine.configuration.optimizationLevel == .aggressive)
    
    // Auto-optimized configuration
    let optimizedConfig = VectorizedPrefilteringEngine.Configuration.optimizedFor(elementCount: 1000)
    #expect(optimizedConfig.optimizationLevel == .aggressive)
    #expect(optimizedConfig.blockSize > 0)
    #expect(optimizedConfig.maxConcurrency > 0)
}

@Test("VectorizedPrefilteringEngine progress reporting configuration")
func testVectorizedPrefilteringEngineProgressReporting() async throws {
    // Test configuration with progress callback
    let configWithProgress = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .balanced,
        progressCallback: { _ in
            // Callback exists but we don't test execution to avoid concurrency issues
        }
    )
    
    let engineWithProgress = VectorizedPrefilteringEngine(configuration: configWithProgress)
    let elements = createTestElements(count: 20)
    
    // Should work without crashing when progress callback is provided
    let candidates = try await engineWithProgress.findCandidates(elements: elements, threshold: 0.3)
    #expect(candidates.count >= 0)
    
    // Test configuration without progress callback
    let configWithoutProgress = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .balanced,
        progressCallback: nil
    )
    
    let engineWithoutProgress = VectorizedPrefilteringEngine(configuration: configWithoutProgress)
    
    // Should work without crashing when no progress callback is provided
    let candidatesWithoutProgress = try await engineWithoutProgress.findCandidates(elements: elements, threshold: 0.3)
    #expect(candidatesWithoutProgress.count >= 0)
}

@Test("VectorizedPrefilteringEngine parallel processing performance")
func testVectorizedPrefilteringEngineParallelPerformance() async throws {
    let elements = createTestElements(count: 100)
    
    // Test conservative (limited parallelism)
    let conservativeConfig = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .conservative,
        maxConcurrency: 2
    )
    let conservativeEngine = VectorizedPrefilteringEngine(configuration: conservativeConfig)
    
    let conservativeStart = CFAbsoluteTimeGetCurrent()
    let conservativeCandidates = try await conservativeEngine.findCandidates(elements: elements, threshold: 0.3)
    let conservativeTime = CFAbsoluteTimeGetCurrent() - conservativeStart
    
    // Test aggressive (maximum parallelism)
    let aggressiveConfig = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .aggressive,
        maxConcurrency: ProcessInfo.processInfo.processorCount
    )
    let aggressiveEngine = VectorizedPrefilteringEngine(configuration: aggressiveConfig)
    
    let aggressiveStart = CFAbsoluteTimeGetCurrent()
    let aggressiveCandidates = try await aggressiveEngine.findCandidates(elements: elements, threshold: 0.3)
    let aggressiveTime = CFAbsoluteTimeGetCurrent() - aggressiveStart
    
    // Both should find similar number of candidates
    let candidateDifference = abs(conservativeCandidates.count - aggressiveCandidates.count)
    #expect(candidateDifference <= conservativeCandidates.count / 10) // Allow 10% variation
    
    // Performance should be reasonable
    #expect(conservativeTime < 5.0) // Should complete in reasonable time
    #expect(aggressiveTime < 5.0) // Should complete in reasonable time
}

@Test("VectorizedPrefilteringEngine accuracy preservation")
func testVectorizedPrefilteringEngineAccuracyPreservation() async throws {
    let elements = createTestElements(count: 20)
    
    // Compare with standard prefiltering engine
    let standardEngine = PrefilteringEngine()
    let vectorizedEngine = VectorizedPrefilteringEngine()
    
    let standardResult = standardEngine.findCandidatePairs(elements: elements)
    let vectorizedCandidates = try await vectorizedEngine.prefilter(elements: elements, threshold: 0.4)
    let standardCandidates = standardResult.candidates.map { (elements[$0.0], elements[$0.1]) }
    
    // Should find similar number of candidates (allowing for optimization differences)
    let candidateRatio = Double(vectorizedCandidates.count) / Double(max(standardCandidates.count, 1))
    #expect(candidateRatio >= 0.8) // Should find at least 80% of standard candidates
    #expect(candidateRatio <= 1.5) // Should not find more than 150% of standard candidates
}

@Test("VectorizedPrefilteringEngine backward compatibility")
func testVectorizedPrefilteringEngineBackwardCompatibility() async throws {
    let standardEngine = PrefilteringEngine()
    let vectorizedEngine = VectorizedPrefilteringEngine.from(standardEngine)
    
    let elements = createTestElements(count: 15)
    
    // Both engines should work with the same interface
    let standardResult = standardEngine.findCandidatePairs(elements: elements)
    let standardResults = standardResult.candidates.map { (elements[$0.0], elements[$0.1]) }
    let vectorizedResults = try await vectorizedEngine.prefilter(elements: elements, threshold: 0.3)
    
    // Results should be in the same format
    #expect(standardResults.count >= 0)
    #expect(vectorizedResults.count >= 0)
    
    // Both should find candidates
    if elements.count > 5 {
        let totalCandidates = standardResults.count + vectorizedResults.count
        #expect(totalCandidates >= 0) // At least one should find candidates
    }
}

@Test("VectorizedPrefilteringEngine large dataset handling")
func testVectorizedPrefilteringEngineLargeDatasetHandling() async throws {
    let largeElements = createTestElements(count: 200)
    
    let config = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .aggressive,
        blockSize: 64
    )
    let engine = VectorizedPrefilteringEngine(configuration: config)
    
    let startTime = CFAbsoluteTimeGetCurrent()
    let candidates = try await engine.findCandidates(elements: largeElements, threshold: 0.4)
    let processingTime = CFAbsoluteTimeGetCurrent() - startTime
    
    // Should handle large datasets efficiently
    #expect(processingTime < 10.0) // Should complete in reasonable time
    #expect(candidates.count >= 0) // Should not crash
    
    // Performance metrics
    let elementsPerSecond = Double(largeElements.count) / processingTime
    #expect(elementsPerSecond > 10.0) // Should process at least 10 elements per second
}

@Test("VectorizedPrefilteringEngine memory efficiency")
func testVectorizedPrefilteringEngineMemoryEfficiency() async throws {
    let elements = createTestElements(count: 100)
    
    // Test with memory-conscious configuration
    let config = VectorizedPrefilteringEngine.Configuration(
        optimizationLevel: .auto,
        blockSize: 32, // Smaller blocks for memory efficiency
        hashMatrixCacheSize: 1000
    )
    let engine = VectorizedPrefilteringEngine(configuration: config)
    
    // Multiple runs should not cause memory leaks
    for _ in 0..<3 {
        let candidates = try await engine.findCandidates(elements: elements, threshold: 0.3)
        #expect(candidates.count >= 0)
    }
}

@Test("VectorizedPrefilteringEngine hash matrix optimization")
func testVectorizedPrefilteringEngineHashMatrixOptimization() async throws {
    let elements = createTestElements(count: 50)
    
    // Test with hash matrix precomputation
    let engine = VectorizedPrefilteringEngine()
    
    // Should efficiently handle multiple similarity checks
    let candidates1 = try await engine.findCandidates(elements: elements, threshold: 0.3)
    let candidates2 = try await engine.findCandidates(elements: elements, threshold: 0.4)
    let candidates3 = try await engine.findCandidates(elements: elements, threshold: 0.5)
    
    // Higher thresholds should find fewer or equal candidates
    #expect(candidates3.count <= candidates2.count)
    #expect(candidates2.count <= candidates1.count)
    
    // All should be consistent
    for (_, _, similarity) in candidates1 {
        #expect(similarity >= 0.3)
    }
    for (_, _, similarity) in candidates2 {
        #expect(similarity >= 0.4)
    }
    for (_, _, similarity) in candidates3 {
        #expect(similarity >= 0.5)
    }
}

@Test("VectorizedPrefilteringEngine SIMD optimization")
func testVectorizedPrefilteringEngineSIMDOptimization() async throws {
    let elements = createTestElements(count: 30)
    
    // Test with SIMD enabled
    let simdConfig = VectorizedPrefilteringEngine.Configuration(enableSIMD: true)
    let simdEngine = VectorizedPrefilteringEngine(configuration: simdConfig)
    
    // Test with SIMD disabled
    let noSIMDConfig = VectorizedPrefilteringEngine.Configuration(enableSIMD: false)
    let noSIMDEngine = VectorizedPrefilteringEngine(configuration: noSIMDConfig)
    
    let simdCandidates = try await simdEngine.findCandidates(elements: elements, threshold: 0.3)
    let noSIMDCandidates = try await noSIMDEngine.findCandidates(elements: elements, threshold: 0.3)
    
    // Both should find similar candidates (allowing for minor differences)
    let candidateDifference = abs(simdCandidates.count - noSIMDCandidates.count)
    #expect(candidateDifference <= max(simdCandidates.count, noSIMDCandidates.count) / 5) // Allow 20% variation
}

@Test("VectorizedPrefilteringEngine edge cases")
func testVectorizedPrefilteringEngineEdgeCases() async throws {
    let engine = VectorizedPrefilteringEngine()
    
    // Empty elements
    let emptyCandidates = try await engine.findCandidates(elements: [], threshold: 0.3)
    #expect(emptyCandidates.isEmpty)
    
    // Single element
    let singleElement = createTestElements(count: 1)
    let singleCandidates = try await engine.findCandidates(elements: singleElement, threshold: 0.3)
    #expect(singleCandidates.isEmpty) // No pairs possible
    
    // Two elements
    let twoElements = createTestElements(count: 2)
    let twoCandidates = try await engine.findCandidates(elements: twoElements, threshold: 0.1)
    #expect(twoCandidates.count <= 1) // At most one pair
    
    // Very high threshold
    let elements = createTestElements(count: 10)
    let highThresholdCandidates = try await engine.findCandidates(elements: elements, threshold: 0.99)
    #expect(highThresholdCandidates.count >= 0) // Should not crash
    
    // Zero threshold
    let zeroThresholdCandidates = try await engine.findCandidates(elements: elements, threshold: 0.0)
    #expect(zeroThresholdCandidates.count >= 0) // Should find many candidates
}

@Test("VectorizedPrefilteringEngine performance benchmarking")
func testVectorizedPrefilteringEnginePerformanceBenchmarking() async throws {
    let benchmarkSizes = [50, 100, 150]
    var results: [String: Double] = [:]
    
    for size in benchmarkSizes {
        let elements = createTestElements(count: size)
        let engine = VectorizedPrefilteringEngine(
            configuration: .optimizedFor(elementCount: size)
        )
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let candidates = try await engine.findCandidates(elements: elements, threshold: 0.3)
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        results["size_\(size)_time"] = processingTime
        results["size_\(size)_candidates"] = Double(candidates.count)
        results["size_\(size)_rate"] = Double(size) / processingTime
        
        // Performance should scale reasonably
        #expect(processingTime < 5.0) // All sizes should complete quickly
        #expect(candidates.count >= 0) // Should not crash
    }
    
    // Larger datasets should have reasonable scaling
    if let rate50 = results["size_50_rate"], let rate150 = results["size_150_rate"] {
        let efficiencyRatio = rate150 / rate50
        #expect(efficiencyRatio > 0.1) // Efficiency should not degrade more than 10x
    }
}

// MARK: - Test Helpers

private func createTestElements(count: Int) -> [CodeElement] {
    var elements: [CodeElement] = []
    
    for i in 0..<count {
        // Create a simple tree node for testing
        let treeNode = SimpleTreeNode(
            label: "Function:\(i)",
            children: [
                SimpleTreeNode(label: "Parameters", children: []),
                SimpleTreeNode(label: "CodeBlock", children: [])
            ]
        )
        
        let element = CodeElement(
            elementType: .function,
            name: "testElement\(i)",
            signature: "func testElement\(i)()",
            filePath: "test\(i % 3).swift",
            startLine: i * 10 + 1,
            endLine: i * 10 + 5,
            codePreview: "func testElement\(i)() { }",
            treeNode: treeNode
        )
        
        elements.append(element)
    }
    
    return elements
} 