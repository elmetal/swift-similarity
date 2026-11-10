import Testing
@testable import swift_similarity

@Test("AdvancedSimilarityMetrics configuration weights within normalization tolerance")
func testAdvancedMetricsConfigurationCreation() {
    let defaultConfig = AdvancedSimilarityMetrics.Configuration()
    #expect(defaultConfig.structuralWeight > 0.0)
    #expect(defaultConfig.labelWeight > 0.0)
    #expect(defaultConfig.depthWeight > 0.0)
    
    // Weights should sum to 1.0 within floating point tolerance
    let weightSum = defaultConfig.structuralWeight + defaultConfig.labelWeight + defaultConfig.depthWeight
    let tolerance = 0.001
    let normalizedRange = (1.0 - tolerance)...(1.0 + tolerance)
    #expect(normalizedRange.contains(weightSum))
}

@Test("AdvancedSimilarityMetrics identical trees within floating point tolerance")
func testIdenticalTreesWithinTolerance() {
    let tree1 = SimpleTreeNode(label: "A", children: [
        SimpleTreeNode(label: "B"),
        SimpleTreeNode(label: "C")
    ])
    
    let tree2 = SimpleTreeNode(label: "A", children: [
        SimpleTreeNode(label: "B"),
        SimpleTreeNode(label: "C")
    ])
    
    let metrics = AdvancedSimilarityMetrics()
    let result = metrics.calculateAdvancedSimilarity(between: tree1, and: tree2)
    
    // Define tolerance range for floating point precision
    let tolerance = 0.001
    let perfectSimilarityRange = (1.0 - tolerance)...(1.0 + tolerance)
    
    // Verify all similarity metrics are within tolerance of perfect similarity (1.0)
    #expect(perfectSimilarityRange.contains(result.overallSimilarity))
    #expect(perfectSimilarityRange.contains(result.structuralSimilarity))
    #expect(perfectSimilarityRange.contains(result.labelSimilarity))
    #expect(perfectSimilarityRange.contains(result.depthSimilarity))
}

@Test("AdvancedSimilarityMetrics custom weights produce valid similarity scores")
func testCustomWeights() {
    let tree1 = SimpleTreeNode(label: "A")
    let tree2 = SimpleTreeNode(label: "B")
    
    // Define valid similarity score range
    let validSimilarityRange = 0.0...1.0
    
    // High structural weight configuration
    let structuralConfig = AdvancedSimilarityMetrics.Configuration(
        structuralWeight: 0.8,
        labelWeight: 0.1,
        depthWeight: 0.1
    )
    let structuralMetrics = AdvancedSimilarityMetrics(configuration: structuralConfig)
    let structuralResult = structuralMetrics.calculateAdvancedSimilarity(between: tree1, and: tree2)
    
    // High label weight configuration
    let labelConfig = AdvancedSimilarityMetrics.Configuration(
        structuralWeight: 0.1,
        labelWeight: 0.8,
        depthWeight: 0.1
    )
    let labelMetrics = AdvancedSimilarityMetrics(configuration: labelConfig)
    let labelResult = labelMetrics.calculateAdvancedSimilarity(between: tree1, and: tree2)
    
    // All similarity scores should be within valid range
    #expect(validSimilarityRange.contains(structuralResult.overallSimilarity))
    #expect(validSimilarityRange.contains(structuralResult.structuralSimilarity))
    #expect(validSimilarityRange.contains(structuralResult.labelSimilarity))
    #expect(validSimilarityRange.contains(structuralResult.depthSimilarity))
    
    #expect(validSimilarityRange.contains(labelResult.overallSimilarity))
    #expect(validSimilarityRange.contains(labelResult.structuralSimilarity))
    #expect(validSimilarityRange.contains(labelResult.labelSimilarity))
    #expect(validSimilarityRange.contains(labelResult.depthSimilarity))
    
    // Different weight configurations should produce different overall similarities
    #expect(structuralResult.overallSimilarity != labelResult.overallSimilarity)
}

@Test("A TSED score the caller already has is reported as is, with the same other metrics")
func testKnownTSEDIsReused() {
    let tree1 = SimpleTreeNode(label: "A", children: [SimpleTreeNode(label: "B"), SimpleTreeNode(label: "C")])
    let tree2 = SimpleTreeNode(label: "A", children: [SimpleTreeNode(label: "B")])
    let metrics = AdvancedSimilarityMetrics()
    let computed = metrics.calculateAdvancedSimilarity(between: tree1, and: tree2)
    let reused = metrics.calculateAdvancedSimilarity(between: tree1, and: tree2, tsed: computed.aptedSimilarity)

    #expect(abs(computed.aptedSimilarity - 2.0 / 3.0) < 1e-9)
    #expect(reused.aptedSimilarity == computed.aptedSimilarity)
    #expect(reused.overallSimilarity == computed.overallSimilarity)
    #expect(metrics.calculateAdvancedSimilarity(between: tree1, and: tree2, tsed: 0.25).aptedSimilarity == 0.25)
}
