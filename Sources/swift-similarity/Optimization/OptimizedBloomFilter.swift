import Foundation

// MARK: - Optimized Bloom Filter

/// A highly optimized memory-efficient probabilistic data structure for fast set membership testing.
/// Uses UInt64 bit vectors instead of Bool arrays for 8x memory reduction and improved cache performance.
public struct OptimizedBloomFilter {
    /// Bit vector storage using UInt64 words (64 bits per word)
    private var bitVector: [UInt64]
    /// Number of hash functions to use
    private let hashFunctionCount: Int
    /// Size of the bit array (in bits)
    private let size: Int
    /// Number of UInt64 words in the bit vector
    private let wordCount: Int
    /// Expected number of elements
    private let expectedElements: Int
    /// Target false positive rate
    private let falsePositiveRate: Double
    
    /// Creates an optimized bloom filter with optimal size for expected elements and false positive rate
    /// - Parameters:
    ///   - expectedElements: Expected number of elements to be inserted
    ///   - falsePositiveRate: Target false positive rate (default: 0.1)
    public init(expectedElements: Int, falsePositiveRate: Double = 0.1) {
        self.expectedElements = expectedElements
        self.falsePositiveRate = falsePositiveRate
        
        // Calculate optimal bit array size: m = -n * ln(p) / (ln(2)^2)
        let optimalSize = max(64, Int(ceil(-Double(expectedElements) * log(falsePositiveRate) / pow(log(2.0), 2))))
        self.size = optimalSize
        
        // Calculate number of UInt64 words needed (round up to nearest word boundary)
        self.wordCount = (optimalSize + 63) / 64
        
        // Calculate optimal number of hash functions: k = (m/n) * ln(2)
        let optimalHashCount = max(1, Int(round(Double(optimalSize) / Double(expectedElements) * log(2.0))))
        self.hashFunctionCount = min(optimalHashCount, 10) // Cap at 10 hash functions for performance
        
        // Initialize bit vector with zeros
        self.bitVector = Array(repeating: 0, count: wordCount)
    }
    
    /// Sets a bit at the specified index
    /// - Parameter index: Bit index to set
    @inline(__always)
    private mutating func setBit(at index: Int) {
        let wordIndex = index / 64
        let bitIndex = index % 64
        bitVector[wordIndex] |= (1 << bitIndex)
    }
    
    /// Gets the value of a bit at the specified index
    /// - Parameter index: Bit index to check
    /// - Returns: True if the bit is set, false otherwise
    @inline(__always)
    private func getBit(at index: Int) -> Bool {
        let wordIndex = index / 64
        let bitIndex = index % 64
        return (bitVector[wordIndex] & (1 << bitIndex)) != 0
    }
    
    /// Adds a fingerprint to the optimized bloom filter
    /// - Parameter fingerprint: The AST node fingerprint to add
    public mutating func add(_ fingerprint: ASTNodeFingerprint) {
        let hashValues = fingerprint.hashValues(hashCount: hashFunctionCount)
        
        for hashValue in hashValues {
            let index = abs(hashValue) % size
            setBit(at: index)
        }
    }
    
    /// Checks if a fingerprint might be in the optimized bloom filter
    /// - Parameter fingerprint: The AST node fingerprint to check
    /// - Returns: True if the fingerprint might be in the set (false positives possible), false if definitely not in the set
    public func contains(_ fingerprint: ASTNodeFingerprint) -> Bool {
        let hashValues = fingerprint.hashValues(hashCount: hashFunctionCount)
        
        for hashValue in hashValues {
            let index = abs(hashValue) % size
            if !getBit(at: index) {
                return false // Definitely not in the set
            }
        }
        
        return true // Might be in the set (could be false positive)
    }
    
    /// Checks if two fingerprints might be similar based on optimized bloom filter analysis
    /// - Parameters:
    ///   - fingerprint1: First fingerprint
    ///   - fingerprint2: Second fingerprint
    ///   - threshold: Similarity threshold for early rejection (default: 0.3)
    /// - Returns: True if fingerprints might be similar (worth detailed comparison)
    public func mightBeSimilar(_ fingerprint1: ASTNodeFingerprint, _ fingerprint2: ASTNodeFingerprint, threshold: Double = 0.3) -> Bool {
        // Quick size-based rejection
        guard fingerprint1.mightBeSimilar(to: fingerprint2, sizeRatioThreshold: threshold) else {
            return false
        }
        
        // Get hash values for both fingerprints
        let hashes1 = fingerprint1.hashValues(hashCount: hashFunctionCount)
        let hashes2 = fingerprint2.hashValues(hashCount: hashFunctionCount)
        
        // Calculate intersection count using direct comparison (avoiding Set operations)
        var intersectionCount = 0
        var unionCount = 0
        var seen = Set<Int>()
        
        // Add all hash positions from both fingerprints to seen set and count intersection
        for hash in hashes1 {
            let position = abs(hash) % size
            seen.insert(position)
        }
        
        for hash in hashes2 {
            let position = abs(hash) % size
            if seen.contains(position) {
                intersectionCount += 1
            } else {
                seen.insert(position)
            }
        }
        
        unionCount = seen.count
        let jaccardSimilarity = unionCount > 0 ? Double(intersectionCount) / Double(unionCount) : 1.0
        
        // Allow through if Jaccard similarity suggests potential match
        return jaccardSimilarity >= threshold * 0.5 // Use a relaxed threshold for bloom filter
    }
    
    /// Returns information about the optimized bloom filter configuration
    /// - Returns: Dictionary containing filter statistics
    public func getStatistics() -> [String: Any] {
        // Count set bits using bit manipulation
        var setBits = 0
        for word in bitVector {
            setBits += word.nonzeroBitCount
        }
        
        let loadFactor = Double(setBits) / Double(size)
        let memoryUsageBytes = wordCount * 8 // 8 bytes per UInt64
        let memoryReductionFactor = Double(size) / Double(memoryUsageBytes) // Compared to Bool array
        
        return [
            "size": size,
            "word_count": wordCount,
            "hash_functions": hashFunctionCount,
            "expected_elements": expectedElements,
            "target_false_positive_rate": falsePositiveRate,
            "set_bits": setBits,
            "load_factor": loadFactor,
            "memory_usage_bytes": memoryUsageBytes,
            "memory_reduction_factor": memoryReductionFactor
        ]
    }
    
    /// Returns the current memory usage in bytes
    public var memoryUsage: Int {
        return wordCount * 8 // 8 bytes per UInt64 word
    }
    
    /// Returns the memory usage that would be required by a Bool array implementation
    public var memoryUsageIfBoolArray: Int {
        return size * MemoryLayout<Bool>.size // Bool array memory usage
    }
    
    /// Returns the memory reduction factor compared to Bool array
    public var memoryReductionFactor: Double {
        return Double(memoryUsageIfBoolArray) / Double(memoryUsage)
    }
}

// MARK: - Optimized Bloom Filter Factory

extension OptimizedBloomFilter {
    /// Creates an optimized bloom filter for AST fingerprint comparison
    /// - Parameters:
    ///   - elementCount: Number of code elements to be processed
    ///   - targetAccuracy: Desired accuracy (1.0 - false positive rate) (default: 0.9)
    /// - Returns: Configured optimized bloom filter
    public static func forASTFingerprints(elementCount: Int, targetAccuracy: Double = 0.9) -> OptimizedBloomFilter {
        let falsePositiveRate = 1.0 - targetAccuracy
        let adjustedElementCount = elementCount * (elementCount - 1) / 2 // Estimate for pairwise comparisons
        
        return OptimizedBloomFilter(expectedElements: adjustedElementCount, falsePositiveRate: falsePositiveRate)
    }
    
    /// Creates a small optimized bloom filter for testing purposes
    /// - Returns: Small optimized bloom filter suitable for unit tests
    public static func forTesting() -> OptimizedBloomFilter {
        return OptimizedBloomFilter(expectedElements: 10, falsePositiveRate: 0.1)
    }
}

// MARK: - Backward Compatibility

extension OptimizedBloomFilter {
    /// Creates an OptimizedBloomFilter with the same configuration as a standard BloomFilter
    /// - Parameter bloomFilter: The standard bloom filter to migrate from
    /// - Returns: Equivalent optimized bloom filter
    public static func from(_ bloomFilter: BloomFilter) -> OptimizedBloomFilter {
        let stats = bloomFilter.getStatistics()
        let expectedElements = stats["expected_elements"] as? Int ?? 100
        let falsePositiveRate = stats["target_false_positive_rate"] as? Double ?? 0.1
        
        return OptimizedBloomFilter(expectedElements: expectedElements, falsePositiveRate: falsePositiveRate)
    }
} 