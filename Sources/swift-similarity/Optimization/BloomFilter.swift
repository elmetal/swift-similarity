import Foundation

// MARK: - Bloom Filter

/// A memory-efficient probabilistic data structure for fast set membership testing.
/// Used to quickly eliminate obviously dissimilar AST fingerprint pairs before expensive APTED calculation.
public struct BloomFilter {
    /// Bit array for bloom filter storage
    private var bitArray: [Bool]
    /// Number of hash functions to use
    private let hashFunctionCount: Int
    /// Size of the bit array
    private let size: Int
    /// Expected number of elements
    private let expectedElements: Int
    /// Target false positive rate
    private let falsePositiveRate: Double
    
    /// Creates a bloom filter with optimal size for expected elements and false positive rate
    /// - Parameters:
    ///   - expectedElements: Expected number of elements to be inserted
    ///   - falsePositiveRate: Target false positive rate (default: 0.1)
    public init(expectedElements: Int, falsePositiveRate: Double = 0.1) {
        self.expectedElements = expectedElements
        self.falsePositiveRate = falsePositiveRate
        
        // Calculate optimal bit array size: m = -n * ln(p) / (ln(2)^2)
        let optimalSize = max(1, Int(ceil(-Double(expectedElements) * log(falsePositiveRate) / pow(log(2.0), 2))))
        self.size = optimalSize
        
        // Calculate optimal number of hash functions: k = (m/n) * ln(2)
        let optimalHashCount = max(1, Int(round(Double(optimalSize) / Double(expectedElements) * log(2.0))))
        self.hashFunctionCount = min(optimalHashCount, 10) // Cap at 10 hash functions for performance
        
        // Initialize bit array
        self.bitArray = Array(repeating: false, count: size)
    }
    
    /// Adds a fingerprint to the bloom filter
    /// - Parameter fingerprint: The AST node fingerprint to add
    public mutating func add(_ fingerprint: ASTNodeFingerprint) {
        let hashValues = fingerprint.hashValues(hashCount: hashFunctionCount)
        
        for hashValue in hashValues {
            let index = abs(hashValue) % size
            bitArray[index] = true
        }
    }
    
    /// Checks if a fingerprint might be in the bloom filter
    /// - Parameter fingerprint: The AST node fingerprint to check
    /// - Returns: True if the fingerprint might be in the set (false positives possible), false if definitely not in the set
    public func contains(_ fingerprint: ASTNodeFingerprint) -> Bool {
        let hashValues = fingerprint.hashValues(hashCount: hashFunctionCount)
        
        for hashValue in hashValues {
            let index = abs(hashValue) % size
            if !bitArray[index] {
                return false // Definitely not in the set
            }
        }
        
        return true // Might be in the set (could be false positive)
    }
    
    /// Checks if two fingerprints might be similar based on bloom filter analysis
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
        let hashes1 = Set(fingerprint1.hashValues(hashCount: hashFunctionCount).map { abs($0) % size })
        let hashes2 = Set(fingerprint2.hashValues(hashCount: hashFunctionCount).map { abs($0) % size })
        
        // Calculate Jaccard similarity of hash positions
        let intersection = hashes1.intersection(hashes2)
        let union = hashes1.union(hashes2)
        
        let jaccardSimilarity = union.count > 0 ? Double(intersection.count) / Double(union.count) : 1.0
        
        // Allow through if Jaccard similarity suggests potential match
        return jaccardSimilarity >= threshold * 0.5 // Use a relaxed threshold for bloom filter
    }
    
    /// Returns information about the bloom filter configuration
    /// - Returns: Dictionary containing filter statistics
    public func getStatistics() -> [String: Any] {
        let setBits = bitArray.filter { $0 }.count
        let loadFactor = Double(setBits) / Double(size)
        
        return [
            "size": size,
            "hash_functions": hashFunctionCount,
            "expected_elements": expectedElements,
            "target_false_positive_rate": falsePositiveRate,
            "set_bits": setBits,
            "load_factor": loadFactor
        ]
    }
}

// MARK: - Bloom Filter Factory

extension BloomFilter {
    /// Creates a bloom filter optimized for AST fingerprint comparison
    /// - Parameters:
    ///   - elementCount: Number of code elements to be processed
    ///   - targetAccuracy: Desired accuracy (1.0 - false positive rate) (default: 0.9)
    /// - Returns: Configured bloom filter
    public static func forASTFingerprints(elementCount: Int, targetAccuracy: Double = 0.9) -> BloomFilter {
        let falsePositiveRate = 1.0 - targetAccuracy
        let adjustedElementCount = elementCount * (elementCount - 1) / 2 // Estimate for pairwise comparisons
        
        return BloomFilter(expectedElements: adjustedElementCount, falsePositiveRate: falsePositiveRate)
    }
    
    /// Creates a small bloom filter for testing purposes
    /// - Returns: Small bloom filter suitable for unit tests
    public static func forTesting() -> BloomFilter {
        return BloomFilter(expectedElements: 10, falsePositiveRate: 0.1)
    }
}
