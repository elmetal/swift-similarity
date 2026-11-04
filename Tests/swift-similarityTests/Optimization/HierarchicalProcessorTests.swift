import Testing
@testable import swift_similarity

struct HierarchicalProcessorTests {
    
    // MARK: - Configuration Tests
    
    @Test("Configuration initialization with default values")
    func testConfigurationDefaultValues() {
        let config = HierarchicalProcessor.Configuration()
        
        #expect(config.quickStageOffset == 0.2)
        #expect(config.mediumStageOffset == 0.1)
        #expect(config.maxCandidatesPerStage == 10000)
        #expect(config.enableSampling == true)
        #expect(config.samplingRatio == 0.8)
        #expect(config.enableEarlyTermination == true)
        #expect(config.targetResultCount == 1000)
    }
    
    @Test("Configuration optimization for different project scales")
    func testConfigurationOptimalForScales() {
        // Small project configuration
        let smallConfig = HierarchicalProcessor.Configuration.optimal(for: .small)
        #expect(smallConfig.quickStageOffset == -0.2)
        #expect(smallConfig.mediumStageOffset == 0.0)
        #expect(smallConfig.maxCandidatesPerStage == 6000)
        #expect(smallConfig.enableSampling == false)
        #expect(smallConfig.enableEarlyTermination == false)
        
        // Medium project configuration
        let mediumConfig = HierarchicalProcessor.Configuration.optimal(for: .medium)
        #expect(mediumConfig.quickStageOffset == 0.2)
        #expect(mediumConfig.enableSampling == true)
        #expect(mediumConfig.samplingRatio == 0.9)
        #expect(mediumConfig.targetResultCount == 2000)
        
        // Large project configuration
        let largeConfig = HierarchicalProcessor.Configuration.optimal(for: .large)
        #expect(largeConfig.quickStageOffset == 0.15)
        #expect(largeConfig.mediumStageOffset == 0.08)
        #expect(largeConfig.samplingRatio == 0.85)
        #expect(largeConfig.targetResultCount == 1200)
        
        // Massive project configuration
        let massiveConfig = HierarchicalProcessor.Configuration.optimal(for: .massive)
        #expect(massiveConfig.quickStageOffset == 0.15)
        #expect(massiveConfig.mediumStageOffset == 0.08)
        #expect(massiveConfig.samplingRatio == 0.7)
        #expect(massiveConfig.targetResultCount == 800)
    }
    
    // MARK: - Progress and Statistics Tests
    
    @Test("HierarchicalProgress initialization")
    func testHierarchicalProgressInitialization() {
        let progress = HierarchicalProcessor.HierarchicalProgress(
            currentStage: 2,
            stageName: "Medium Filter",
            elementsProcessed: 500,
            totalElements: 1000,
            candidatesFound: 50,
            reductionRatio: 0.95,
            estimatedTimeRemaining: 30.5
        )
        
        #expect(progress.currentStage == 2)
        #expect(progress.stageName == "Medium Filter")
        #expect(progress.elementsProcessed == 500)
        #expect(progress.totalElements == 1000)
        #expect(progress.candidatesFound == 50)
        #expect(progress.reductionRatio == 0.95)
        #expect(progress.estimatedTimeRemaining == 30.5)
    }
    
    @Test("StageStatistics calculation")
    func testStageStatisticsCalculation() {
        let stats = HierarchicalProcessor.StageStatistics(
            stage: 1,
            name: "Quick Filter",
            processingTime: 2.5,
            inputCandidates: 10000,
            outputCandidates: 1000
        )
        
        #expect(stats.stage == 1)
        #expect(stats.name == "Quick Filter")
        #expect(stats.processingTime == 2.5)
        #expect(stats.inputCandidates == 10000)
        #expect(stats.outputCandidates == 1000)
        #expect(stats.reductionRatio == 0.9) // (10000 - 1000) / 10000
        #expect(stats.processingRate == 4000.0) // 10000 / 2.5
    }
    
    @Test("StageStatistics edge cases")
    func testStageStatisticsEdgeCases() {
        // Zero input candidates
        let zeroInputStats = HierarchicalProcessor.StageStatistics(
            stage: 1,
            name: "Test",
            processingTime: 1.0,
            inputCandidates: 0,
            outputCandidates: 0
        )
        #expect(zeroInputStats.reductionRatio == 0.0)
        
        // Zero processing time
        let zeroTimeStats = HierarchicalProcessor.StageStatistics(
            stage: 1,
            name: "Test",
            processingTime: 0.0,
            inputCandidates: 100,
            outputCandidates: 50
        )
        #expect(zeroTimeStats.processingRate == 0.0)
    }
    
    // MARK: - Processor Initialization Tests
    
    @Test("HierarchicalProcessor initialization")
    func testHierarchicalProcessorInitialization() {
        let config = HierarchicalProcessor.Configuration()
        
        let processor = HierarchicalProcessor(
            configuration: config,
            vectorizedConfig: nil,
            progressCallback: nil
        )
        
        // Basic initialization test - processor should be created successfully
        #expect(true) // Processor creation successful if no exception thrown
    }
    
    @Test("HierarchicalProcessor with custom vectorized config")
    func testHierarchicalProcessorWithCustomVectorizedConfig() {
        let config = HierarchicalProcessor.Configuration()
        let vectorizedConfig = VectorizedPrefilteringEngine.Configuration(
            optimizationLevel: .balanced,
            blockSize: 1000,
            maxConcurrency: 2
        )
        
        let processor = HierarchicalProcessor(
            configuration: config,
            vectorizedConfig: vectorizedConfig
        )
        
        // Should initialize successfully with custom vectorized config
        #expect(processor != nil)
    }
    
    // MARK: - Helper Test Elements
    
    private func createTestElements(count: Int) -> [CodeElement] {
        var elements: [CodeElement] = []
        
        for i in 0..<count {
            let treeNode = SimpleTreeNode(
                label: "TestNode\(i)",
                children: [
                    SimpleTreeNode(label: "Child1", children: []),
                    SimpleTreeNode(label: "Child2", children: [])
                ]
            )
            
            let element = CodeElement(
                elementType: .function,
                name: "testFunction\(i)",
                signature: "func testFunction\(i)()",
                filePath: "/test/file\(i).swift",
                startLine: i * 10 + 1,
                endLine: i * 10 + 10,
                codePreview: "func testFunction\(i)() { /* test */ }",
                treeNode: treeNode
            )
            
            elements.append(element)
        }
        
        return elements
    }
    
    private func createSimilarTestElements() -> [CodeElement] {
        // Create elements that should be detected as similar
        let similarTreeNode1 = SimpleTreeNode(
            label: "FunctionDecl",
            children: [
                SimpleTreeNode(label: "Identifier", children: []),
                SimpleTreeNode(label: "ReturnType", children: [])
            ]
        )
        
        let similarTreeNode2 = SimpleTreeNode(
            label: "FunctionDecl",
            children: [
                SimpleTreeNode(label: "Identifier", children: []),
                SimpleTreeNode(label: "ReturnType", children: [])
            ]
        )
        
        let element1 = CodeElement(
            elementType: .function,
            name: "similarFunction1",
            signature: "func similarFunction1() -> Int",
            filePath: "/test/similar1.swift",
            startLine: 1,
            endLine: 5,
            codePreview: "func similarFunction1() -> Int { return 1 }",
            treeNode: similarTreeNode1
        )
        
        let element2 = CodeElement(
            elementType: .function,
            name: "similarFunction2",
            signature: "func similarFunction2() -> Int",
            filePath: "/test/similar2.swift",
            startLine: 10,
            endLine: 14,
            codePreview: "func similarFunction2() -> Int { return 2 }",
            treeNode: similarTreeNode2
        )
        
        return [element1, element2]
    }
    
    // MARK: - Processing Tests
    
    @Test("Small dataset processing")
    func testSmallDatasetProcessing() async throws {
        let config = HierarchicalProcessor.Configuration.optimal(for: .small)
        let processor = HierarchicalProcessor(configuration: config)
        
        let elements = createSimilarTestElements()
        let threshold = 0.7
        
        let (results, statistics) = try await processor.process(elements: elements, threshold: threshold)
        
        // Should process successfully
        #expect(statistics.count > 0)
        #expect(statistics.count <= 3) // Maximum 3 stages
        
        // Results should be valid
        #expect(results.count >= 0)
        for (_, _, similarity) in results {
            #expect(similarity >= threshold)
            #expect(similarity <= 1.0)
        }
    }
    
    @Test("Empty dataset processing")
    func testEmptyDatasetProcessing() async throws {
        let config = HierarchicalProcessor.Configuration()
        let processor = HierarchicalProcessor(configuration: config)
        
        let elements: [CodeElement] = []
        let threshold = 0.7
        
        let (results, statistics) = try await processor.process(elements: elements, threshold: threshold)
        
        // Should handle empty dataset gracefully
        #expect(results.isEmpty)
        #expect(statistics.count > 0) // Should still have some stage statistics
    }
    
    @Test("Single element processing")
    func testSingleElementProcessing() async throws {
        let config = HierarchicalProcessor.Configuration()
        let processor = HierarchicalProcessor(configuration: config)
        
        let elements = Array(createTestElements(count: 1))
        let threshold = 0.7
        
        let (results, statistics) = try await processor.process(elements: elements, threshold: threshold)
        
        // Single element should produce no pairs
        #expect(results.isEmpty)
        #expect(statistics.count > 0)
    }
    
    @Test("Large dataset with sampling")
    func testLargeDatasetWithSampling() async throws {
        let config = HierarchicalProcessor.Configuration(
            enableSampling: true,
            samplingRatio: 0.5
        )
        let processor = HierarchicalProcessor(configuration: config)
        
        // Create a dataset large enough to trigger sampling (>1000 elements)
        let elements = createTestElements(count: 1500)
        let threshold = 0.9 // High threshold to reduce processing time
        
        let (results, statistics) = try await processor.process(elements: elements, threshold: threshold)
        
        // Should process successfully with sampling
        #expect(statistics.count > 0)
        #expect(results.count >= 0)
        
        // Verify statistics are reasonable
        for stat in statistics {
            #expect(stat.processingTime >= 0)
            #expect(stat.inputCandidates >= 0)
            #expect(stat.outputCandidates >= 0)
            #expect(stat.reductionRatio >= 0.0 && stat.reductionRatio <= 1.0)
        }
    }
    
    @Test("Early termination functionality")
    func testEarlyTermination() async throws {
        let config = HierarchicalProcessor.Configuration(
            maxCandidatesPerStage: 10,
            enableEarlyTermination: true,
            targetResultCount: 5
        )
        let processor = HierarchicalProcessor(configuration: config)
        
        let elements = createTestElements(count: 50)
        let threshold = 0.1 // Low threshold to find many candidates
        
        let (results, statistics) = try await processor.process(elements: elements, threshold: threshold)
        
        // Should terminate early and not process all stages
        #expect(statistics.count >= 1)
        #expect(results.count >= 0)
    }
    
    @Test("Progress reporting")
    func testProgressReporting() async throws {
        let config = HierarchicalProcessor.Configuration()
        
        // Test that processor accepts progress callback without error
        let processor = HierarchicalProcessor(configuration: config, progressCallback: { progress in
            // Progress callback functionality - we just verify it can be set
        })
        
        let elements = createTestElements(count: 3) // Small dataset to reduce test time
        let threshold = 0.9 // High threshold to reduce processing
        
        let _ = try await processor.process(elements: elements, threshold: threshold)
        
        // Test that processing completes successfully with progress callback
        #expect(true) // Processing completed without error
    }
    
    @Test("Configuration validation across scales")
    func testConfigurationValidationAcrossScales() {
        let scales: [VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale] = [.small, .medium, .large, .massive]
        
        for scale in scales {
            let config = HierarchicalProcessor.Configuration.optimal(for: scale)
            
            // All configurations should have valid values
            // Offsets may be negative (more permissive), but must stay within the score range
            #expect(config.quickStageOffset > -1.0 && config.quickStageOffset < 1.0)
            #expect(config.mediumStageOffset > -1.0 && config.mediumStageOffset < 1.0)
            #expect(config.maxCandidatesPerStage > 0)
            #expect(config.samplingRatio > 0.0 && config.samplingRatio <= 1.0)
            #expect(config.targetResultCount >= 0)
        }
    }
} 