import Foundation

// MARK: - Advanced Similarity Metrics

/// Advanced similarity metrics that combine multiple indicators for better accuracy.
public class AdvancedSimilarityMetrics {
    
    /// Configuration for advanced metrics calculation.
    public struct Configuration {
        /// Weight for structural similarity (0.0-1.0).
        public let structuralWeight: Double
        /// Weight for label similarity (0.0-1.0).
        public let labelWeight: Double
        /// Weight for depth similarity (0.0-1.0).
        public let depthWeight: Double
        /// Tree edit operation costs for the APTED-based (TSED) score.
        public let aptedCosts: APTED.OperationCosts
        
        /// Creates advanced metrics configuration.
        public init(structuralWeight: Double = 0.6, labelWeight: Double = 0.3, depthWeight: Double = 0.1, aptedCosts: APTED.OperationCosts = APTED.OperationCosts()) {
            self.aptedCosts = aptedCosts
            let total = structuralWeight + labelWeight + depthWeight
            self.structuralWeight = structuralWeight / total
            self.labelWeight = labelWeight / total
            self.depthWeight = depthWeight / total
        }
    }
    
    /// Advanced similarity result with detailed metrics.
    public struct AdvancedSimilarityResult {
        /// Overall combined similarity score (0.0-1.0).
        public let overallSimilarity: Double
        /// Structural similarity score (0.0-1.0).
        public let structuralSimilarity: Double
        /// Label similarity score (0.0-1.0).
        public let labelSimilarity: Double
        /// Depth similarity score (0.0-1.0).
        public let depthSimilarity: Double
        /// Basic APTED-based similarity.
        public let aptedSimilarity: Double
        
        /// Creates an advanced similarity result.
        public init(overallSimilarity: Double, structuralSimilarity: Double, labelSimilarity: Double, depthSimilarity: Double, aptedSimilarity: Double) {
            self.overallSimilarity = overallSimilarity
            self.structuralSimilarity = structuralSimilarity
            self.labelSimilarity = labelSimilarity
            self.depthSimilarity = depthSimilarity
            self.aptedSimilarity = aptedSimilarity
        }
    }
    
    /// Configuration for this metrics calculator.
    public let configuration: Configuration
    
    /// Basic similarity calculator for APTED results.
    private let basicCalculator: SimilarityCalculator
    
    /// Creates an advanced similarity metrics calculator.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.basicCalculator = SimilarityCalculator(configuration: .init(aptedCosts: configuration.aptedCosts))
    }
    
    /// Calculates advanced similarity metrics between two trees.
    /// - Parameters:
    ///   - tree1: First tree
    ///   - tree2: Second tree
    ///   - tsed: The trees' TSED score with this calculator's costs, when the caller already has
    ///     it (a scan does); nil computes it, which costs a full tree edit distance
    /// - Returns: Advanced similarity result with detailed metrics
    public func calculateAdvancedSimilarity(between tree1: TreeNode, and tree2: TreeNode, tsed: Double? = nil) -> AdvancedSimilarityResult {
        let aptedSimilarity = tsed ?? basicCalculator.calculateSimilarity(between: tree1, and: tree2).similarityScore
        
        // Calculate individual metrics
        let structuralSim = calculateJaccardSimilarity(
            set1: collectTreeData(tree1) { node in "node_\(node.children.count)_children" },
            set2: collectTreeData(tree2) { node in "node_\(node.children.count)_children" }
        )
        let labelSim = calculateJaccardSimilarity(
            set1: collectTreeData(tree1) { node in node.label },
            set2: collectTreeData(tree2) { node in node.label }
        )
        let depthSim = calculateDepthSimilarity(tree1, tree2)
        
        // Combine metrics using weights
        let overallSim = (structuralSim * configuration.structuralWeight) +
                        (labelSim * configuration.labelWeight) +
                        (depthSim * configuration.depthWeight)
        
        return AdvancedSimilarityResult(
            overallSimilarity: overallSim,
            structuralSimilarity: structuralSim,
            labelSimilarity: labelSim,
            depthSimilarity: depthSim,
            aptedSimilarity: aptedSimilarity
        )
    }
    
    /// Calculates Jaccard similarity coefficient between two arrays of comparable elements.
    /// - Parameters:
    ///   - set1: First array of elements
    ///   - set2: Second array of elements
    /// - Returns: Jaccard similarity coefficient (0.0 to 1.0)
    private func calculateJaccardSimilarity<T: Hashable>(set1: [T], set2: [T]) -> Double {
        let setA = Set(set1)
        let setB = Set(set2)
        
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        
        return union > 0 ? Double(intersection) / Double(union) : 1.0
    }
    
    /// Calculates depth similarity based on tree depths.
    private func calculateDepthSimilarity(_ tree1: TreeNode, _ tree2: TreeNode) -> Double {
        let depth1 = calculateDepth(tree1)
        let depth2 = calculateDepth(tree2)
        
        let maxDepth = max(depth1, depth2)
        let minDepth = min(depth1, depth2)
        
        return maxDepth > 0 ? Double(minDepth) / Double(maxDepth) : 1.0
    }
    
    /// Collects data from tree nodes using a provided collector function.
    /// - Parameters:
    ///   - tree: The tree to traverse
    ///   - collector: Function that extracts data from each node
    /// - Returns: Array of collected data
    private func collectTreeData<T>(_ tree: TreeNode, collector: (TreeNode) -> T) -> [T] {
        var results: [T] = []
        collectTreeDataHelper(tree, &results, collector)
        return results
    }
    
    /// Helper method for generic tree data collection.
    private func collectTreeDataHelper<T>(_ node: TreeNode, _ results: inout [T], _ collector: (TreeNode) -> T) {
        results.append(collector(node))
        for child in node.children {
            collectTreeDataHelper(child, &results, collector)
        }
    }
    
    /// Calculates the depth of a tree.
    private func calculateDepth(_ tree: TreeNode) -> Int {
        if tree.children.isEmpty {
            return 1
        }
        
        let maxChildDepth = tree.children.map { calculateDepth($0) }.max() ?? 0
        return 1 + maxChildDepth
    }
}