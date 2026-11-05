import Foundation
import Testing
@testable import swift_similarity

struct AdaptiveConfigurationTests {
    
    // MARK: - Project Scale Detection Tests
    
    @Test("Project scale detection for different element counts")
    func testProjectScaleDetection() {
        // Small projects (0-10K pairs)
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 100) == .small)
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 141) == .small) // ~10K pairs
        
        // Medium projects (10K-100K pairs)
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 142) == .medium) // ~10K pairs
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 447) == .medium) // ~100K pairs
        
        // Large projects (100K-1M pairs)
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 448) == .large) // ~100K pairs
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 1414) == .large) // ~1M pairs
        
        // Massive projects (1M+ pairs)
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 1415) == .massive) // ~1M pairs
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 10000) == .massive)
    }
    
    @Test("Project scale edge cases")
    func testProjectScaleEdgeCases() {
        // Empty or single element
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 0) == .small)
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 1) == .small)
        
        // Boundary cases
        #expect(VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale.from(elementCount: 2) == .small) // 1 pair
    }
    
    // MARK: - System Resources Tests
    
    @Test("System resources detection")
    func testSystemResourcesDetection() {
        let resources = VectorizedPrefilteringEngine.AdaptiveConfiguration.SystemResources.current()
        
        // Basic validation
        #expect(resources.availableCores > 0)
        #expect(resources.totalMemory > 0)
        #expect(resources.availableMemory > 0)
        #expect(resources.cpuLoad >= 0.0 && resources.cpuLoad <= 1.0)
        
        // Reasonable values
        #expect(resources.availableCores <= 64) // Reasonable upper bound
        #expect(resources.availableMemory <= resources.totalMemory)
    }
    
    // MARK: - Adaptive Configuration Generation Tests
    
    @Test("Small project configuration")
    func testSmallProjectConfiguration() {
        let config = VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: 100)
        
        #expect(config.optimizationLevel == .aggressive)
        #expect(config.maxConcurrency > 0)
        #expect(config.blockSize >= 100 && config.blockSize <= 1000)
    }
    
    @Test("Medium project configuration")
    func testMediumProjectConfiguration() {
        let config = VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: 300)
        
        #expect(config.optimizationLevel == .balanced)
        #expect(config.maxConcurrency == ProcessInfo.processInfo.processorCount)
        #expect(config.blockSize >= 500 && config.blockSize <= 2000)
    }
    
    @Test("Large project configuration")
    func testLargeProjectConfiguration() {
        let config = VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: 1000)
        
        #expect(config.optimizationLevel == .conservative)
        #expect(config.maxConcurrency == ProcessInfo.processInfo.processorCount)
        #expect(config.blockSize >= 1000 && config.blockSize <= 5000)
    }
    
    @Test("Massive project configuration")
    func testMassiveProjectConfiguration() {
        let config = VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: 5000)
        
        #expect(config.optimizationLevel == .conservative)
        #expect(config.maxConcurrency == ProcessInfo.processInfo.processorCount)
        #expect(config.blockSize >= 2000 && config.blockSize <= 10000)
    }
    
    // MARK: - Configuration Adjustment Tests
    
    @Test("CPU utilization adjustment")
    func testCPUUtilizationAdjustment() {
        let originalConfig = VectorizedPrefilteringEngine.Configuration(
            optimizationLevel: .balanced,
            maxConcurrency: 8
        )
        
        // High CPU utilization should reduce concurrency
        let adjustedConfig = VectorizedPrefilteringEngine.AdaptiveConfiguration.adjust(
            originalConfig,
            cpuUtilization: 0.9,  // 90% CPU usage
            processingRate: 100.0
        )
        
        #expect(adjustedConfig.maxConcurrency < originalConfig.maxConcurrency)
        #expect(adjustedConfig.maxConcurrency >= 1) // Should not go below 1
    }
    
    @Test("No adjustment needed")
    func testNoAdjustmentNeeded() {
        let originalConfig = VectorizedPrefilteringEngine.Configuration(
            optimizationLevel: .balanced,
            maxConcurrency: 4
        )
        
        // Normal resource usage
        let adjustedConfig = VectorizedPrefilteringEngine.AdaptiveConfiguration.adjust(
            originalConfig,
            cpuUtilization: 0.6,  // Normal CPU
            processingRate: 100.0
        )
        
        #expect(adjustedConfig.maxConcurrency == originalConfig.maxConcurrency)
    }
    
    // MARK: - Integration Tests
    
    @Test("Configuration consistency across scales")
    func testConfigurationConsistency() {
        let scales: [Int] = [50, 200, 800, 3000] // Small, medium, large, massive
        
        for elementCount in scales {
            let config = VectorizedPrefilteringEngine.AdaptiveConfiguration.optimal(for: elementCount)
            
            // All configurations should have valid values
            #expect(config.maxConcurrency > 0)
            #expect(config.blockSize > 0)
        }
    }
} 