import Foundation

// MARK: - AST Node Fingerprint

/// Represents a compact fingerprint of an AST tree for fast similarity pre-filtering.
/// Uses node type counts and structural metrics to enable efficient comparison.
public struct ASTNodeFingerprint {
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
    
    /// Calculates Manhattan distance between two fingerprints
    /// Used for quick similarity estimation before expensive APTED calculation
    /// - Parameter other: The other fingerprint to compare with
    /// - Returns: Distance value (lower means more similar)
    public func distance(to other: ASTNodeFingerprint) -> Double {
        // Calculate Manhattan distance of node type counts
        let allNodeTypes = Set(self.nodeTypeCounts.keys).union(Set(other.nodeTypeCounts.keys))
        var distance: Double = 0
        
        for nodeType in allNodeTypes {
            let count1 = self.nodeTypeCounts[nodeType] ?? 0
            let count2 = other.nodeTypeCounts[nodeType] ?? 0
            distance += abs(Double(count1 - count2))
        }
        
        // Add structural differences
        distance += abs(Double(self.totalNodes - other.totalNodes)) * 0.5
        distance += abs(Double(self.maxDepth - other.maxDepth)) * 2.0
        distance += abs(Double(self.leafNodeCount - other.leafNodeCount)) * 1.5
        distance += abs(Double(self.uniqueNodeTypes - other.uniqueNodeTypes)) * 1.0
        
        return distance
    }
    
    /// Calculates a normalized similarity score based on distance
    /// - Parameter other: The other fingerprint to compare with
    /// - Returns: Similarity score (0.0-1.0, where 1.0 is identical)
    public func similarity(to other: ASTNodeFingerprint) -> Double {
        let distance = self.distance(to: other)
        let maxPossibleDistance = Double(max(self.totalNodes, other.totalNodes)) * 2.0
        
        guard maxPossibleDistance > 0 else { return 1.0 }
        return max(0.0, 1.0 - (distance / maxPossibleDistance))
    }
    
    /// Generates hash values for bloom filter insertion/lookup
    /// - Parameter hashCount: Number of hash functions to use
    /// - Returns: Array of hash values for bloom filter
    public func hashValues(hashCount: Int) -> [Int] {
        var hashValues: [Int] = []
        
        // Create a deterministic string representation for hashing
        let nodeTypeString = nodeTypeCounts.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        
        let structuralString = "\(totalNodes),\(maxDepth),\(leafNodeCount),\(uniqueNodeTypes)"
        let combinedString = "\(nodeTypeString)|\(structuralString)"
        
        // Generate multiple hash values using different seeds
        for i in 0..<hashCount {
            let seed = UInt32(i * 31 + 17) // Use different seeds for each hash function
            let hash = combinedString.djb2Hash(seed: seed)
            hashValues.append(abs(Int(hash)))
        }
        
        return hashValues
    }
    
    /// Checks if two fingerprints are potentially similar based on basic criteria
    /// Used for fast rejection before distance calculation
    /// - Parameters:
    ///   - other: The other fingerprint to compare
    ///   - sizeRatioThreshold: Minimum size ratio threshold (default: 0.3)
    /// - Returns: True if fingerprints might be similar
    public func mightBeSimilar(to other: ASTNodeFingerprint, sizeRatioThreshold: Double = 0.3) -> Bool {
        // Quick size ratio check
        let minNodes = min(self.totalNodes, other.totalNodes)
        let maxNodes = max(self.totalNodes, other.totalNodes)
        let sizeRatio = maxNodes > 0 ? Double(minNodes) / Double(maxNodes) : 1.0
        
        guard sizeRatio >= sizeRatioThreshold else { return false }
        
        // Depth difference check
        let depthDifference = abs(self.maxDepth - other.maxDepth)
        guard depthDifference <= max(self.maxDepth, other.maxDepth) / 2 else { return false }
        
        // Node type diversity check
        let commonNodeTypes = Set(self.nodeTypeCounts.keys).intersection(Set(other.nodeTypeCounts.keys))
        let totalUniqueTypes = Set(self.nodeTypeCounts.keys).union(Set(other.nodeTypeCounts.keys))
        let typeOverlap = totalUniqueTypes.count > 0 ? Double(commonNodeTypes.count) / Double(totalUniqueTypes.count) : 1.0
        
        guard typeOverlap >= 0.2 else { return false }
        
        return true
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

// MARK: - String Hashing Extension

private extension String {
    /// DJB2 hash function with configurable seed
    /// - Parameter seed: Seed value for hash function
    /// - Returns: Hash value
    func djb2Hash(seed: UInt32 = 5381) -> UInt32 {
        var hash = seed
        for byte in self.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return hash
    }
}