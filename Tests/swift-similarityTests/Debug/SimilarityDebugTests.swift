import Testing
import Foundation
@testable import swift_similarity

// MARK: - Similarity Calculation Debug Tests

/// Debug tests for investigating the false 100% similarity between different functions
struct SimilarityDebugTests {
    
    @Test("Debug similarity calculation between collectTreeDataHelper and BloomFilter contains")
    func testProblematicSimilarityCalculation() async throws {
        
        // Test 1: Extract actual CodeElements for the problematic functions
        let advancedSimilarityFile = "Sources/swift-similarity/Calculator/AdvancedSimilarityMetrics.swift"
        let bloomFilterFile = "Sources/swift-similarity/Optimization/BloomFilter.swift"
        
        let extractor = CodeElementExtractor()
        let advancedElements = try extractor.extractElements(from: advancedSimilarityFile)
        let bloomElements = try extractor.extractElements(from: bloomFilterFile)
        
        // Find the specific functions
        var collectTreeDataHelper: CodeElement?
        for element in advancedElements {
            if element.name == "collectTreeDataHelper" && element.startLine == 136 && element.endLine == 141 {
                collectTreeDataHelper = element
                break
            }
        }
        
        var containsFunction: CodeElement?
        for element in bloomElements {
            if element.name == "contains" && element.startLine >= 53 && element.endLine <= 64 {
                containsFunction = element
                break
            }
        }
        
        #expect(collectTreeDataHelper != nil, "collectTreeDataHelper function should be found")
        #expect(containsFunction != nil, "contains function should be found")
        
        guard let func1 = collectTreeDataHelper, let func2 = containsFunction else {
            return
        }
        
        print("=== DEBUG: Function 1 ===")
        print("Name: \(func1.name)")
        print("Lines: \(func1.startLine)-\(func1.endLine)")
        print("Code: \(func1.codePreview)")
        print("Tree structure: \(func1.treeNode)")
        
        print("\n=== DEBUG: Function 2 ===")
        print("Name: \(func2.name)")
        print("Lines: \(func2.startLine)-\(func2.endLine)")
        print("Code: \(func2.codePreview)")
        print("Tree structure: \(func2.treeNode)")
        
        // Test 2: Calculate similarity with basic metrics
        let basicCalculator = SimilarityCalculator()
        let basicResult = basicCalculator.calculateSimilarity(
            between: func1.treeNode, 
            and: func2.treeNode
        )
        
        print("\n=== BASIC SIMILARITY ===")
        print("Similarity Score: \(basicResult.similarityScore)")
        print("Edit Distance: \(basicResult.editDistance)")
        print("Are Similar: \(basicResult.areSimilar)")
        print("Metadata: \(basicResult.metadata)")
        
        // Test 3: Calculate similarity with advanced metrics
        let advancedCalculator = AdvancedSimilarityMetrics()
        let advancedResult = advancedCalculator.calculateAdvancedSimilarity(
            between: func1.treeNode, 
            and: func2.treeNode
        )
        
        print("\n=== ADVANCED SIMILARITY ===")
        print("Overall Similarity: \(advancedResult.overallSimilarity)")
        print("Structural Similarity: \(advancedResult.structuralSimilarity)")
        print("Label Similarity: \(advancedResult.labelSimilarity)")
        print("Depth Similarity: \(advancedResult.depthSimilarity)")
        print("APTED Similarity: \(advancedResult.aptedSimilarity)")
        
        // Test 4: Manual APTED calculation debug
        let apted = APTED()
        let editDistance = apted.editDistance(between: func1.treeNode, and: func2.treeNode)
        print("\n=== MANUAL APTED DEBUG ===")
        print("Raw Edit Distance: \(editDistance)")
        
        // Expectations: These functions should NOT be 100% similar
        #expect(basicResult.similarityScore < 0.99, "Basic similarity should be < 99%")
        #expect(advancedResult.overallSimilarity < 0.99, "Advanced similarity should be < 99%")
        
        // If similarity is unexpectedly high, flag for investigation
        if basicResult.similarityScore >= 0.99 || advancedResult.overallSimilarity >= 0.99 {
            print("\n🚨 PROBLEM DETECTED: Unexpectedly high similarity!")
            print("This indicates a bug in the similarity calculation logic.")
        }
    }
    
    @Test("Debug TreeNode structure comparison")
    func testTreeNodeStructureDebug() throws {
        
        // Create simplified test trees to understand the comparison
        let simpleTree1 = SimpleTreeNode(
            label: "function",
            children: [
                SimpleTreeNode(label: "parameter_list", children: []),
                SimpleTreeNode(label: "code_block", children: [
                    SimpleTreeNode(label: "for_statement", children: [])
                ])
            ]
        )
        
        let simpleTree2 = SimpleTreeNode(
            label: "function", 
            children: [
                SimpleTreeNode(label: "parameter_list", children: []),
                SimpleTreeNode(label: "code_block", children: [
                    SimpleTreeNode(label: "for_statement", children: [])
                ])
            ]
        )
        
        let calculator = SimilarityCalculator()
        let result = calculator.calculateSimilarity(between: simpleTree1, and: simpleTree2)
        
        print("=== SIMPLE TREE COMPARISON ===")
        print("Tree 1: \(simpleTree1)")
        print("Tree 2: \(simpleTree2)")
        print("Similarity: \(result.similarityScore)")
        print("Edit Distance: \(result.editDistance)")
        
        // Identical trees should have 100% similarity and 0 edit distance
        #expect(result.similarityScore == 1.0)
        #expect(result.editDistance == 0)
    }
} 