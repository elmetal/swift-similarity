import Foundation

// MARK: - AST Node Fingerprint

/// Represents a compact fingerprint of an AST tree for fast similarity pre-filtering.
/// Uses node type counts and structural metrics to enable efficient comparison.
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
    
    /// Generates hash values for bloom filter insertion/lookup (optimized)
    /// - Parameter hashCount: Number of hash functions to use
    /// - Returns: Array of hash values for bloom filter
    public func hashValues(hashCount: Int) -> [Int] {
        return fastHashValues(hashCount: hashCount)
    }
    
    /// High-performance hash value generation with zero-allocation design
    /// Uses direct numeric operations instead of string-based hashing
    /// - Parameter hashCount: Number of hash functions to use
    /// - Returns: Array of hash values for bloom filter
    public func fastHashValues(hashCount: Int) -> [Int] {
        // Pre-allocate result array
        var hashValues: [Int] = []
        hashValues.reserveCapacity(hashCount)
        
        // Calculate base hash components using numeric operations
        let baseHash = calculateBaseHash()
        let nodeTypeHash = calculateNodeTypeHash()
        
        // Generate multiple hash values using bit manipulation
        for i in 0..<hashCount {
            let seedA = UInt64(i * 31 + 17)
            let seedB = UInt64(i * 47 + 23)
            
            // Combine base hash with seeds using bit manipulation
            let hash1 = baseHash ^ (seedA &* 0x9e3779b97f4a7c15)
            let hash2 = nodeTypeHash ^ (seedB &* 0x85ebca6b54321ba9)
            
            // Final hash mixing
            let finalHash = hash1 &+ hash2
            hashValues.append(abs(Int(truncatingIfNeeded: finalHash)))
        }
        
        return hashValues
    }
    
    /// Calculates base hash from structural properties using bit manipulation
    /// - Returns: 64-bit hash value
    @inline(__always)
    private func calculateBaseHash() -> UInt64 {
        var hash: UInt64 = 0
        
        // Mix structural properties using bit operations
        hash ^= UInt64(totalNodes) &* 0x517cc1b727220a95
        hash ^= UInt64(maxDepth) &* 0x27d4eb2d165787ad
        hash ^= UInt64(leafNodeCount) &* 0x7c159c3e8d6e4521
        hash ^= UInt64(uniqueNodeTypes) &* 0x46495ac983f7a3d1
        
        // Final mixing
        hash ^= hash >> 33
        hash &*= 0xff51afd7ed558ccd
        hash ^= hash >> 33
        
        return hash
    }
    
    /// Calculates node type hash using direct key-value processing
    /// - Returns: 64-bit hash value
    @inline(__always)  
    private func calculateNodeTypeHash() -> UInt64 {
        var hash: UInt64 = 0
        
        // Process node types in deterministic order without string operations
        for (key, value) in nodeTypeCounts.sorted(by: { $0.key < $1.key }) {
            // Hash the key using its hashValue (avoiding string operations)
            let keyHash = UInt64(bitPattern: Int64(key.hashValue))
            let valueHash = UInt64(value)
            
            // Combine key and value hash
            let combinedHash = keyHash &* 0x9e3779b97f4a7c15 ^ valueHash &* 0x85ebca6b54321ba9
            
            // Accumulate using XOR and multiplication
            hash ^= combinedHash
            hash &*= 0x6fb4b8b4d7e4c3a1
        }
        
        return hash
    }
    
    /// Checks if two fingerprints are potentially similar based on basic criteria
    /// Used for fast rejection before distance calculation (optimized)
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
        
        // Optimized node type diversity check using direct comparison
        let typeOverlap = calculateTypeOverlapRatio(with: other)
        guard typeOverlap >= 0.2 else { return false }
        
        return true
    }
    
    /// Calculates type overlap ratio without Set operations for better performance
    /// - Parameter other: The other fingerprint to compare
    /// - Returns: Overlap ratio (0.0 - 1.0)
    @inline(__always)
    private func calculateTypeOverlapRatio(with other: ASTNodeFingerprint) -> Double {
        let selfKeys = self.nodeTypeCounts.keys
        let otherKeys = other.nodeTypeCounts.keys
        
        // Early termination for empty cases
        if selfKeys.isEmpty && otherKeys.isEmpty { return 1.0 }
        if selfKeys.isEmpty || otherKeys.isEmpty { return 0.0 }
        
        // Count intersections using direct iteration (avoiding Set operations)
        var commonCount = 0
        var totalUniqueCount = 0
        var processedKeys = Set<String>()
        processedKeys.reserveCapacity(selfKeys.count + otherKeys.count)
        
        // Process self keys
        for key in selfKeys {
            processedKeys.insert(key)
            if other.nodeTypeCounts[key] != nil {
                commonCount += 1
            }
        }
        
        // Process other keys (only new ones)
        for key in otherKeys {
            processedKeys.insert(key)
        }
        
        totalUniqueCount = processedKeys.count
        
        return totalUniqueCount > 0 ? Double(commonCount) / Double(totalUniqueCount) : 1.0
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

// MARK: - Hash Caching Extension

extension ASTNodeFingerprint {
    /// Cached hash values for repeated calculations
    /// Protected by cacheQueue for thread safety
    private nonisolated(unsafe) static var hashCache: [ASTNodeFingerprint: [Int: [Int]]] = [:]
    private static let cacheQueue = DispatchQueue(label: "hash-cache", attributes: .concurrent)
    
    /// Gets cached hash values or calculates new ones
    /// - Parameter hashCount: Number of hash functions to use
    /// - Returns: Cached or newly calculated hash values
    public func cachedHashValues(hashCount: Int) -> [Int] {
        return Self.cacheQueue.sync {
            if let cachedValues = Self.hashCache[self]?[hashCount] {
                return cachedValues
            }
            
            // Calculate new hash values
            let newValues = fastHashValues(hashCount: hashCount)
            
            // Cache the results (with size limit to prevent memory leaks)
            Self.cacheQueue.async(flags: .barrier) {
                if Self.hashCache.count > 1000 { // Limit cache size
                    Self.hashCache.removeAll()
                }
                
                if Self.hashCache[self] == nil {
                    Self.hashCache[self] = [:]
                }
                Self.hashCache[self]![hashCount] = newValues
            }
            
            return newValues
        }
    }
    
    /// Clears the hash cache (for testing or memory management)
    public static func clearHashCache() {
        cacheQueue.async(flags: .barrier) {
            hashCache.removeAll()
        }
    }
}

// MARK: - Hash Benchmarking Extension

extension ASTNodeFingerprint {
    /// Benchmarks hash calculation performance
    /// - Parameters:
    ///   - iterations: Number of iterations to run
    ///   - hashCount: Number of hash functions to use
    /// - Returns: Dictionary with performance metrics
    public func benchmarkHashPerformance(iterations: Int = 10000, hashCount: Int = 5) -> [String: Any] {
        let startTime = ProcessInfo.processInfo.systemUptime
        
        for _ in 0..<iterations {
            let _ = fastHashValues(hashCount: hashCount)
        }
        
        let endTime = ProcessInfo.processInfo.systemUptime
        let totalTime = endTime - startTime
        let averageTimeMs = (totalTime * 1000.0) / Double(iterations)
        let operationsPerSecond = Double(iterations) / totalTime
        
        return [
            "total_time_seconds": totalTime,
            "average_time_ms": averageTimeMs,
            "operations_per_second": operationsPerSecond,
            "iterations": iterations,
            "hash_count": hashCount
        ]
    }
    
    /// Tests hash distribution quality
    /// - Parameter hashCount: Number of hash functions to test
    /// - Returns: Distribution quality metrics
    public func testHashDistribution(hashCount: Int = 5, bucketCount: Int = 1000) -> [String: Any] {
        let hashValues = fastHashValues(hashCount: hashCount)
        var buckets = Array(repeating: 0, count: bucketCount)
        
        // Distribute hash values into buckets
        for hash in hashValues {
            let bucketIndex = abs(hash) % bucketCount
            buckets[bucketIndex] += 1
        }
        
        // Calculate distribution metrics
        let nonEmptyBuckets = buckets.filter { $0 > 0 }.count
        let maxBucketCount = buckets.max() ?? 0
        let minBucketCount = buckets.filter { $0 > 0 }.min() ?? 0
        let averageBucketCount = Double(hashValues.count) / Double(nonEmptyBuckets)
        
        return [
            "non_empty_buckets": nonEmptyBuckets,
            "max_bucket_count": maxBucketCount,
            "min_bucket_count": minBucketCount,
            "average_bucket_count": averageBucketCount,
            "distribution_ratio": Double(nonEmptyBuckets) / Double(bucketCount)
        ]
    }
}