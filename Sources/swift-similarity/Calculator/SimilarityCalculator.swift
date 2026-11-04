import Foundation

// MARK: - Similarity Calculator

/// Calculates similarity scores between code structures using APTED results.
public class SimilarityCalculator {
    
    /// Configuration for similarity calculation.
    public struct Configuration {
        /// Threshold for considering two trees similar (0.0-1.0).
        public let similarityThreshold: Double
        /// APTED operation costs to use.
        public let aptedCosts: APTED.OperationCosts
        
        /// Creates similarity configuration with specified values.
        /// - Parameters:
        ///   - similarityThreshold: Similarity threshold (default: 0.8)
        ///   - aptedCosts: APTED operation costs (default: unit costs)
        public init(similarityThreshold: Double = 0.8, aptedCosts: APTED.OperationCosts = APTED.OperationCosts()) {
            self.similarityThreshold = similarityThreshold
            self.aptedCosts = aptedCosts
        }
    }
    
    /// Similarity calculation result.
    public struct SimilarityResult {
        /// Raw edit distance calculated by APTED.
        public let editDistance: Double
        /// Normalized similarity score (0.0-1.0, where 1.0 is identical).
        public let similarityScore: Double
        /// Whether the trees are considered similar based on threshold.
        public let areSimilar: Bool
        /// Additional metadata about the comparison.
        public let metadata: [String: Any]
        
        /// Creates a similarity result.
        /// - Parameters:
        ///   - editDistance: Raw edit distance
        ///   - similarityScore: Normalized similarity score
        ///   - areSimilar: Whether trees are similar
        ///   - metadata: Additional metadata
        public init(editDistance: Double, similarityScore: Double, areSimilar: Bool, metadata: [String: Any] = [:]) {
            self.editDistance = editDistance
            self.similarityScore = similarityScore
            self.areSimilar = areSimilar
            self.metadata = metadata
        }
    }
    
    /// Configuration for this calculator.
    public let configuration: Configuration
    
    /// APTED algorithm instance.
    private let apted: APTED
    
    /// Creates a similarity calculator with specified configuration.
    /// - Parameter configuration: The configuration to use
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.apted = APTED(costs: configuration.aptedCosts)
    }
    
    /// Calculates similarity between two trees.
    /// - Parameters:
    ///   - tree1: First tree
    ///   - tree2: Second tree
    /// - Returns: Similarity calculation result
    public func calculateSimilarity(between tree1: TreeNode, and tree2: TreeNode) -> SimilarityResult {
        // Calculate raw edit distance
        let editDistance = apted.editDistance(between: tree1, and: tree2)
        
        // TSED normalization (arXiv:2404.08817): max(1 - δ / MaxNodes(G1, G2), 0).
        // The ramp keeps the score in [0, 1] when operation costs exceed 1.
        let maxPossibleDistance = Double(max(countNodes(tree1), countNodes(tree2)))
        let similarityScore = maxPossibleDistance > 0 ? max(1.0 - (editDistance / maxPossibleDistance), 0.0) : 1.0
        
        // Determine if trees are similar
        let areSimilar = similarityScore >= configuration.similarityThreshold
        
        // Collect metadata
        let metadata: [String: Any] = [
            "tree1_node_count": countNodes(tree1),
            "tree2_node_count": countNodes(tree2),
            "max_possible_distance": maxPossibleDistance,
            "threshold": configuration.similarityThreshold
        ]
        
        return SimilarityResult(
            editDistance: editDistance,
            similarityScore: similarityScore,
            areSimilar: areSimilar,
            metadata: metadata
        )
    }
    
    /// Returns the TSED score if it can reach `minimumSimilarity`, or nil otherwise.
    ///
    /// Before computing the tree edit distance, this checks a cheap O(|T1|·|T2|) lower bound of
    /// the distance (`APTED.lowerBound`). If even that bound puts the score below
    /// `minimumSimilarity`, the expensive computation is skipped. The bound is exact, so no pair
    /// reaching the threshold is ever rejected.
    /// - Parameters:
    ///   - tree1: First tree
    ///   - tree2: Second tree
    ///   - minimumSimilarity: The TSED score the pair must reach
    /// - Returns: The TSED score when it is at least `minimumSimilarity`, otherwise nil
    public func similarity(between tree1: TreeNode, and tree2: TreeNode, atLeast minimumSimilarity: Double) -> Double? {
        let maxNodes = Double(max(countNodes(tree1), countNodes(tree2)))
        guard maxNodes > 0 else { return 1.0 >= minimumSimilarity ? 1.0 : nil }
        
        let upperBound = max(1.0 - apted.lowerBound(between: tree1, and: tree2) / maxNodes, 0.0)
        guard upperBound >= minimumSimilarity else { return nil }
        
        let score = max(1.0 - apted.editDistance(between: tree1, and: tree2) / maxNodes, 0.0)
        return score >= minimumSimilarity ? score : nil
    }
    
    /// Counts the total number of nodes in a tree.
    /// - Parameter tree: The tree to count nodes in
    /// - Returns: Total number of nodes
    private func countNodes(_ tree: TreeNode) -> Int {
        var count = 1 // Count the current node
        for child in tree.children {
            count += countNodes(child)
        }
        return count
    }
    

} 