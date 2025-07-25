import Foundation

// MARK: - APTED Algorithm

/// APTED (All-Pairs Tree Edit Distance) algorithm implementation.
/// Computes the edit distance between two trees efficiently.
public class APTED {
    
    /// Operation costs for tree edit operations.
    public struct OperationCosts {
        /// Cost of inserting a node.
        public let insertion: Double
        /// Cost of deleting a node.
        public let deletion: Double
        /// Cost of substituting a node label.
        public let substitution: Double
        
        /// Creates operation costs with specified values.
        /// - Parameters:
        ///   - insertion: Cost of insertion (default: 1.0)
        ///   - deletion: Cost of deletion (default: 1.0)
        ///   - substitution: Cost of substitution (default: 1.0)
        public init(insertion: Double = 1.0, deletion: Double = 1.0, substitution: Double = 1.0) {
            self.insertion = insertion
            self.deletion = deletion
            self.substitution = substitution
        }
    }
    
    /// The operation costs used for calculations.
    public let costs: OperationCosts
    
    /// Creates an APTED calculator with specified operation costs.
    /// - Parameter costs: The operation costs to use
    public init(costs: OperationCosts = OperationCosts()) {
        self.costs = costs
    }
    
    /// Computes the edit distance between two trees.
    /// - Parameters:
    ///   - tree1: The first tree
    ///   - tree2: The second tree
    /// - Returns: The edit distance between the trees
    public func editDistance(between tree1: TreeNode, and tree2: TreeNode) -> Double {
        return computeEditDistance(tree1, tree2)
    }
    
    /// Core edit distance computation using dynamic programming.
    /// - Parameters:
    ///   - tree1: The first tree
    ///   - tree2: The second tree
    /// - Returns: The computed edit distance
    private func computeEditDistance(_ tree1: TreeNode, _ tree2: TreeNode) -> Double {
        // Get all nodes in post-order traversal
        let nodes1 = postOrderTraversal(tree1)
        let nodes2 = postOrderTraversal(tree2)
        
        // Initialize distance matrix
        let m = nodes1.count
        let n = nodes2.count
        var distanceMatrix = Array(repeating: Array(repeating: 0.0, count: n + 1), count: m + 1)
        
        // Initialize base cases
        for i in 0...m {
            distanceMatrix[i][0] = Double(i) * costs.deletion
        }
        for j in 0...n {
            distanceMatrix[0][j] = Double(j) * costs.insertion
        }
        
        // Fill the distance matrix
        for i in 1...m {
            for j in 1...n {
                let node1 = nodes1[i - 1]
                let node2 = nodes2[j - 1]
                
                // Calculate costs for different operations
                let deletionCost = distanceMatrix[i - 1][j] + costs.deletion
                let insertionCost = distanceMatrix[i][j - 1] + costs.insertion
                let substitutionCost = distanceMatrix[i - 1][j - 1] + substitutionCost(node1, node2)
                
                // Take minimum cost
                distanceMatrix[i][j] = min(deletionCost, insertionCost, substitutionCost)
            }
        }
        
        return distanceMatrix[m][n]
    }
    
    /// Performs post-order traversal of a tree.
    /// - Parameter tree: The tree to traverse
    /// - Returns: Array of nodes in post-order
    private func postOrderTraversal(_ tree: TreeNode) -> [TreeNode] {
        var result: [TreeNode] = []
        postOrderHelper(tree, &result)
        return result
    }
    
    /// Helper method for post-order traversal.
    /// - Parameters:
    ///   - node: Current node
    ///   - result: Result array to append to
    private func postOrderHelper(_ node: TreeNode, _ result: inout [TreeNode]) {
        for child in node.children {
            postOrderHelper(child, &result)
        }
        result.append(node)
    }
    
    /// Calculates the substitution cost between two nodes.
    /// - Parameters:
    ///   - node1: First node
    ///   - node2: Second node
    /// - Returns: Substitution cost (0.0 if labels match, substitution cost otherwise)
    private func substitutionCost(_ node1: TreeNode, _ node2: TreeNode) -> Double {
        return node1.label == node2.label ? 0.0 : costs.substitution
    }
} 