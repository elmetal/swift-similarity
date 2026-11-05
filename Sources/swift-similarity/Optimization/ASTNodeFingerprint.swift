import Foundation

// MARK: - AST Node Fingerprint

/// A compact summary of a tree (label histogram and size metrics) used for exact pre-filtering.
///
/// `tsedUpperBound(to:)` bounds the TSED score from the label histograms alone, so pairs that
/// cannot reach the threshold are skipped without computing the tree edit distance.
public struct ASTNodeFingerprint: Hashable, Sendable {
    /// Count of each node type in the AST (e.g., "FunctionCallExprSyntax": 5)
    public let nodeTypeCounts: [String: Int]
    /// Total number of nodes in the tree
    public let totalNodes: Int
    /// Maximum depth of the tree
    public let maxDepth: Int
    /// Number of leaf nodes (nodes with no children)
    public let leafNodeCount: Int
    /// Number of distinct node types
    public let uniqueNodeTypes: Int
    
    /// Creates an AST node fingerprint
    /// - Parameters:
    ///   - nodeTypeCounts: Count of each node type
    ///   - totalNodes: Total number of nodes
    ///   - maxDepth: Maximum depth of the tree
    ///   - leafNodeCount: Number of leaf nodes
    public init(nodeTypeCounts: [String: Int], totalNodes: Int, maxDepth: Int, leafNodeCount: Int) {
        self.nodeTypeCounts = nodeTypeCounts
        self.totalNodes = totalNodes
        self.maxDepth = maxDepth
        self.leafNodeCount = leafNodeCount
        self.uniqueNodeTypes = nodeTypeCounts.count
    }
    
    // MARK: - Exact TSED bounds

    /// Lower bound of the tree edit distance from this tree to `other`, derived from label histograms.
    ///
    /// `nodeTypeCounts` must be keyed by node label (as built from `TreeNode.label`).
    /// Labels that occur more often in this tree (`excessSelf` nodes in total) must be deleted or
    /// renamed, and labels that occur more often in `other` (`excessOther`) must be inserted or
    /// renamed; one rename can fix one of each. Minimizing over the number of renames gives a bound
    /// that is never larger than the true distance.
    public func treeEditDistanceLowerBound(to other: ASTNodeFingerprint, costs: APTED.OperationCosts = APTED.OperationCosts()) -> Double {
        var excessSelf = 0
        var excessOther = 0
        for (label, count) in nodeTypeCounts {
            let otherCount = other.nodeTypeCounts[label] ?? 0
            if count > otherCount { excessSelf += count - otherCount }
        }
        for (label, count) in other.nodeTypeCounts {
            let selfCount = nodeTypeCounts[label] ?? 0
            if count > selfCount { excessOther += count - selfCount }
        }
        return Self.treeEditDistanceLowerBound(excessSelf: excessSelf, excessOther: excessOther, costs: costs)
    }

    /// The histogram bound from the number of surplus labels on each side (shared with
    /// `PreparedTree`, so both compute exactly the same value).
    static func treeEditDistanceLowerBound(excessSelf: Int, excessOther: Int, costs: APTED.OperationCosts) -> Double {
        // Cost is linear in the number of renames, so the minimum is at one of the endpoints.
        let noRenames = Double(excessSelf) * costs.deletion + Double(excessOther) * costs.insertion
        let renames = min(excessSelf, excessOther)
        let maxRenames = Double(renames) * costs.substitution
            + Double(excessSelf - renames) * costs.deletion
            + Double(excessOther - renames) * costs.insertion
        return min(noRenames, maxRenames)
    }

    /// Upper bound of the TSED similarity between the trees, `max(1 - δ_lower / MaxNodes, 0)`.
    ///
    /// Pairs whose upper bound is below the threshold can be skipped without computing the tree
    /// edit distance and without any false negatives.
    public func tsedUpperBound(to other: ASTNodeFingerprint, costs: APTED.OperationCosts = APTED.OperationCosts()) -> Double {
        Self.tsedUpperBound(
            distanceLowerBound: treeEditDistanceLowerBound(to: other, costs: costs),
            maxNodes: max(totalNodes, other.totalNodes)
        )
    }

    /// `max(1 - distanceLowerBound / maxNodes, 0)`, or 1 for empty trees
    static func tsedUpperBound(distanceLowerBound: Double, maxNodes: Int) -> Double {
        guard maxNodes > 0 else { return 1.0 }
        return max(1.0 - distanceLowerBound / Double(maxNodes), 0.0)
    }
}

// MARK: - TreeNode Extension

extension TreeNode {
    /// Extracts a fingerprint from this tree node
    /// - Returns: AST node fingerprint containing structural metrics
    public func extractFingerprint() -> ASTNodeFingerprint {
        var nodeTypeCounts: [String: Int] = [:]
        var totalNodes = 0
        var maxDepth = 0
        var leafNodeCount = 0
        
        /// Depth-first traversal to collect statistics
        func traverse(_ node: TreeNode, depth: Int) {
            totalNodes += 1
            maxDepth = max(maxDepth, depth)
            
            // Count node types by their labels
            nodeTypeCounts[node.label, default: 0] += 1
            
            // Count leaf nodes
            if node.children.isEmpty {
                leafNodeCount += 1
            }
            
            // Recursively process children
            for child in node.children {
                traverse(child, depth: depth + 1)
            }
        }
        
        traverse(self, depth: 0)
        
        return ASTNodeFingerprint(
            nodeTypeCounts: nodeTypeCounts,
            totalNodes: totalNodes,
            maxDepth: maxDepth,
            leafNodeCount: leafNodeCount
        )
    }
}
