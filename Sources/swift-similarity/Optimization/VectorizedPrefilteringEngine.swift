import Foundation

// MARK: - Vectorized Prefiltering Engine

/// High-performance vectorized prefiltering engine with batch processing and parallel execution.
/// Designed for maximum throughput when processing large numbers of code elements.
/// Target: 20-50x performance improvement over basic prefiltering.
public final class VectorizedPrefilteringEngine: Sendable {
    
    // MARK: - Configuration
    
    /// Performance optimization level
    public enum OptimizationLevel: String, CaseIterable, Sendable {
        case conservative = "conservative"  // Single-threaded, small batches
        case balanced = "balanced"         // Multi-threaded, medium batches
        case aggressive = "aggressive"     // Maximum parallelism, large batches
        case auto = "auto"                // Adaptive based on system and data size
    }
    
    /// Vectorized processing configuration
    public struct Configuration: Sendable {
        /// Performance optimization level
        public let optimizationLevel: OptimizationLevel
        /// Block size for batch processing (0 = auto-detect)
        public let blockSize: Int
        /// Maximum number of concurrent tasks (0 = auto-detect)
        public let maxConcurrency: Int
        /// Hash matrix cache size limit
        public let hashMatrixCacheSize: Int
        /// Enable SIMD optimizations where available
        public let enableSIMD: Bool
        /// Progress reporting callback
        public let progressCallback: (@Sendable (VectorizedProgress) -> Void)?
        
        public init(
            optimizationLevel: OptimizationLevel = .balanced,
            blockSize: Int = 0,
            maxConcurrency: Int = 0,
            hashMatrixCacheSize: Int = 10000,
            enableSIMD: Bool = true,
            progressCallback: (@Sendable (VectorizedProgress) -> Void)? = nil
        ) {
            self.optimizationLevel = optimizationLevel
            self.blockSize = blockSize
            self.maxConcurrency = maxConcurrency
            self.hashMatrixCacheSize = hashMatrixCacheSize
            self.enableSIMD = enableSIMD
            self.progressCallback = progressCallback
        }
        
        /// Creates configuration optimized for the given element count
        public static func optimizedFor(elementCount: Int) -> Configuration {
            let level: OptimizationLevel
            let blockSize: Int
            let maxConcurrency: Int
            
            if elementCount < 100 {
                level = .conservative
                blockSize = 32
                maxConcurrency = 2
            } else if elementCount < 1000 {
                level = .balanced
                blockSize = 128
                maxConcurrency = 4
            } else {
                level = .aggressive
                blockSize = 512
                maxConcurrency = ProcessInfo.processInfo.processorCount
            }
            
            return Configuration(
                optimizationLevel: level,
                blockSize: blockSize,
                maxConcurrency: maxConcurrency
            )
        }
    }
    
    // MARK: - Adaptive Configuration (Phase 10)
    
    /// Adaptive configuration system for optimal performance across different project scales
    public struct AdaptiveConfiguration: Sendable {
        
        /// Project scale categories based on dataset size
        public enum ProjectScale: String, CaseIterable, Sendable {
            case small = "small"       // 0-10K pairs: Maximum parallelism
            case medium = "medium"     // 10K-100K pairs: Balanced approach
            case large = "large"       // 100K-1M pairs: Conservative parallelism
            case massive = "massive"   // 1M+ pairs: Sequential with optimizations
            
            /// Calculate project scale from element count
            public static func from(elementCount: Int) -> ProjectScale {
                let possiblePairs = elementCount * (elementCount - 1) / 2
                
                switch possiblePairs {
                case 0..<10_000:
                    return .small
                case 10_000..<100_000:
                    return .medium
                case 100_000..<1_000_000:
                    return .large
                default:
                    return .massive
                }
            }
        }
        
        /// System resource monitoring
        public struct SystemResources: Sendable {
            /// Available CPU cores
            public let availableCores: Int
            /// Total memory in bytes
            public let totalMemory: UInt64
            /// Available memory in bytes
            public let availableMemory: UInt64
            /// Current CPU load percentage (0.0-1.0)
            public let cpuLoad: Double
            
            /// Get current system resources
            public static func current() -> SystemResources {
                let cores = ProcessInfo.processInfo.processorCount
                let totalMem = ProcessInfo.processInfo.physicalMemory
                
                // Simplified memory calculation - in production would use sysctl
                let availableMem = totalMem / 2  // Conservative estimate
                
                // Simplified CPU load - in production would use host_cpu_load_info
                let cpuLoad = 0.5  // Conservative estimate
                
                return SystemResources(
                    availableCores: cores,
                    totalMemory: totalMem,
                    availableMemory: availableMem,
                    cpuLoad: cpuLoad
                )
            }
        }
        
        /// Generate optimal configuration for given dataset size and system resources
        public static func optimal(for elementCount: Int, systemResources: SystemResources? = nil) -> Configuration {
            let scale = ProjectScale.from(elementCount: elementCount)
            let resources = systemResources ?? SystemResources.current()
            
            return generateConfiguration(for: scale, resources: resources, elementCount: elementCount)
        }
        
        /// Generate configuration based on project scale and system resources
        private static func generateConfiguration(
            for scale: ProjectScale,
            resources: SystemResources,
            elementCount: Int
        ) -> Configuration {
            switch scale {
            case .small:
                // Small projects: Maximum parallelism for best responsiveness
                return Configuration(
                    optimizationLevel: .aggressive,
                    blockSize: min(1000, max(100, elementCount / 4)),
                    maxConcurrency: resources.availableCores,
                    hashMatrixCacheSize: 5000,
                    enableSIMD: true
                )
                
            case .medium:
                // Medium projects: Balanced approach
                let optimalThreads = max(2, min(resources.availableCores / 2, 8))
                return Configuration(
                    optimizationLevel: .balanced,
                    blockSize: min(2000, max(500, elementCount / 8)),
                    maxConcurrency: optimalThreads,
                    hashMatrixCacheSize: 10000,
                    enableSIMD: true
                )
                
            case .large:
                // Large projects: Conservative parallelism to avoid CPU saturation
                let conservativeThreads = max(2, min(4, resources.availableCores / 2))
                return Configuration(
                    optimizationLevel: .conservative,
                    blockSize: min(5000, max(1000, elementCount / 16)),
                    maxConcurrency: conservativeThreads,
                    hashMatrixCacheSize: 15000,
                    enableSIMD: true
                )
                
            case .massive:
                // Massive projects: Sequential processing with optimizations
                return Configuration(
                    optimizationLevel: .conservative,
                    blockSize: min(10000, max(2000, elementCount / 32)),
                    maxConcurrency: 2,  // Minimal parallelism
                    hashMatrixCacheSize: 20000,
                    enableSIMD: true
                )
            }
        }
        
        /// Adjust configuration based on runtime performance metrics
        public static func adjust(
            _ configuration: Configuration,
            cpuUtilization: Double,
            memoryPressure: Double,
            processingRate: Double
        ) -> Configuration {
            var adjustedConfig = configuration
            
            // If CPU utilization is too high (>80%), reduce parallelism
            if cpuUtilization > 0.8 {
                let reducedConcurrency = max(1, Int(Double(adjustedConfig.maxConcurrency) * 0.7))
                adjustedConfig = Configuration(
                    optimizationLevel: adjustedConfig.optimizationLevel,
                    blockSize: adjustedConfig.blockSize,
                    maxConcurrency: reducedConcurrency,
                    hashMatrixCacheSize: adjustedConfig.hashMatrixCacheSize,
                    enableSIMD: adjustedConfig.enableSIMD,
                    progressCallback: adjustedConfig.progressCallback
                )
            }
            
            // If memory pressure is high (>90%), reduce cache size
            if memoryPressure > 0.9 {
                let reducedCacheSize = Int(Double(adjustedConfig.hashMatrixCacheSize) * 0.5)
                adjustedConfig = Configuration(
                    optimizationLevel: adjustedConfig.optimizationLevel,
                    blockSize: adjustedConfig.blockSize,
                    maxConcurrency: adjustedConfig.maxConcurrency,
                    hashMatrixCacheSize: reducedCacheSize,
                    enableSIMD: adjustedConfig.enableSIMD,
                    progressCallback: adjustedConfig.progressCallback
                )
            }
            
            return adjustedConfig
        }
    }
    
    /// Progress information for vectorized processing
    public struct VectorizedProgress: Sendable {
        public let blocksProcessed: Int
        public let totalBlocks: Int
        public let candidatesFound: Int
        public let processingRate: Double? // blocks per second
        public let estimatedTimeRemaining: Double? // seconds
        public let memoryUsage: Int // bytes
        
        public var completionPercentage: Double {
            return totalBlocks > 0 ? Double(blocksProcessed) / Double(totalBlocks) * 100.0 : 0.0
        }
    }
    
    // MARK: - Internal Types
    
    /// Precomputed hash matrix for efficient similarity checks
    private struct HashMatrix: Sendable {
        let fingerprints: [ASTNodeFingerprint]
        let hashValues: [[Int]]
        let blockSize: Int
        
        init(fingerprints: [ASTNodeFingerprint], hashCount: Int, blockSize: Int) {
            self.fingerprints = fingerprints
            self.blockSize = blockSize
            
            // Precompute all hash values for better cache locality
            self.hashValues = fingerprints.map { $0.fastHashValues(hashCount: hashCount) }
        }
        
        func getHashValues(for index: Int) -> [Int] {
            return hashValues[index]
        }
    }
    
    /// Block of elements for batch processing
    private struct ProcessingBlock: Sendable {
        let startIndex: Int
        let endIndex: Int
        let elements: [CodeElement]
        let matrix: HashMatrix
        
        var size: Int { endIndex - startIndex }
    }
    
    /// Candidate pair result from vectorized processing
    private struct CandidatePair: Sendable {
        let index1: Int
        let index2: Int
        let element1: CodeElement
        let element2: CodeElement
        let similarity: Double
    }
    
    // MARK: - Properties
    
    internal let configuration: Configuration
    private let optimizedBloomFilter: OptimizedBloomFilter
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.optimizedBloomFilter = OptimizedBloomFilter(expectedElements: 10000, falsePositiveRate: 0.01)
    }
    
    // MARK: - Public Interface
    
    /// Performs vectorized prefiltering with maximum performance optimization
    /// - Parameters:
    ///   - elements: Code elements to process
    ///   - threshold: Similarity threshold for candidate selection
    /// - Returns: Array of candidate pairs that pass prefiltering
    public func findCandidates(
        elements: [CodeElement],
        threshold: Double = 0.3
    ) async throws -> [(CodeElement, CodeElement, Double)] {
        guard elements.count >= 2 else { return [] }
        
        let startTime = ProcessInfo.processInfo.systemUptime
        
        // Extract fingerprints with progress reporting (this is the heavy operation)
        var fingerprints: [ASTNodeFingerprint] = []
        for (index, element) in elements.enumerated() {
            let fingerprint = createFingerprint(from: element.treeNode)
            fingerprints.append(fingerprint)
            
            // Report progress during fingerprint creation - more frequent for smaller projects
            let reportInterval = if elements.count < 50 {
                1  // Report every element for small projects
            } else if elements.count < 200 {
                max(1, elements.count / 10)  // Report every 10% for medium projects  
            } else {
                max(1, elements.count / 20)  // Report every 5% for large projects
            }
            
            if index % reportInterval == 0 || index == elements.count - 1 {
                await reportProgress(
                    blocksProcessed: index + 1,
                    totalBlocks: elements.count, // Total elements for fingerprint creation
                    candidatesFound: 0,
                    startTime: startTime
                )
            }
        }
        
        let hashCount = optimizedBloomFilter.hashFunctionCount
        let blockSize = determineOptimalBlockSize(for: elements.count)
        
        let hashMatrix = HashMatrix(
            fingerprints: fingerprints,
            hashCount: hashCount,
            blockSize: blockSize
        )
        
        // Create processing blocks for parallel execution
        let blocks = createProcessingBlocks(elements: elements, matrix: hashMatrix, blockSize: blockSize)
        
        // Report progress after block creation
        await reportProgress(
            blocksProcessed: 0,
            totalBlocks: blocks.count,
            candidatesFound: 0,
            startTime: startTime
        )
        
        // Process blocks in parallel using TaskGroup
        let candidates = try await processBlocksInParallel(blocks: blocks, threshold: threshold, startTime: startTime)
        
        return candidates
    }
    
    // MARK: - Private Implementation
    
    /// Determines optimal block size based on configuration and data characteristics
    private func determineOptimalBlockSize(for elementCount: Int) -> Int {
        if configuration.blockSize > 0 {
            return configuration.blockSize
        }
        
        // Auto-detect optimal block size based on system characteristics
        let processorCount = ProcessInfo.processInfo.processorCount
        let memoryPressure = getMemoryPressure()
        
        switch configuration.optimizationLevel {
        case .conservative:
            return min(64, max(16, elementCount / (processorCount * 4)))
        case .balanced:
            return min(256, max(64, elementCount / (processorCount * 2)))
        case .aggressive:
            return min(1024, max(128, elementCount / processorCount))
        case .auto:
            if memoryPressure > 0.8 {
                return min(128, max(32, elementCount / (processorCount * 3)))
            } else {
                return min(512, max(128, elementCount / processorCount))
            }
        }
    }
    
    /// Creates processing blocks for parallel execution
    private func createProcessingBlocks(
        elements: [CodeElement],
        matrix: HashMatrix,
        blockSize: Int
    ) -> [ProcessingBlock] {
        var blocks: [ProcessingBlock] = []
        let elementCount = elements.count
        
        for startIndex in stride(from: 0, to: elementCount, by: blockSize) {
            let endIndex = min(startIndex + blockSize, elementCount)
            let blockElements = Array(elements[startIndex..<endIndex])
            
            let block = ProcessingBlock(
                startIndex: startIndex,
                endIndex: endIndex,
                elements: blockElements,
                matrix: matrix
            )
            blocks.append(block)
        }
        
        return blocks
    }
    
    /// Processes blocks in parallel using structured concurrency
    private func processBlocksInParallel(
        blocks: [ProcessingBlock],
        threshold: Double,
        startTime: Double
    ) async throws -> [(CodeElement, CodeElement, Double)] {
        let maxConcurrency = configuration.maxConcurrency > 0 
            ? configuration.maxConcurrency 
            : ProcessInfo.processInfo.processorCount
        
        var processedBlocks = 0
        
        return try await withThrowingTaskGroup(of: [CandidatePair].self) { group in
            var results: [(CodeElement, CodeElement, Double)] = []
            
            // Submit initial batch of tasks
            var submittedTasks = 0
            for block in blocks.prefix(maxConcurrency) {
                group.addTask {
                    await self.processBlock(block, threshold: threshold, allBlocks: blocks)
                }
                submittedTasks += 1
            }
            
            // Process results and submit remaining tasks
            for try await blockCandidates in group {
                processedBlocks += 1
                
                // Convert CandidatePair to result format
                for candidate in blockCandidates {
                    results.append((candidate.element1, candidate.element2, candidate.similarity))
                }
                
                // Report progress
                await reportProgress(
                    blocksProcessed: processedBlocks,
                    totalBlocks: blocks.count,
                    candidatesFound: results.count,
                    startTime: startTime
                )
                
                // Submit next task if available
                if submittedTasks < blocks.count {
                    let nextBlock = blocks[submittedTasks]
                    group.addTask {
                        await self.processBlock(nextBlock, threshold: threshold, allBlocks: blocks)
                    }
                    submittedTasks += 1
                }
            }
            
            return results
        }
    }
    
    /// Processes a single block using vectorized operations
    private func processBlock(
        _ block: ProcessingBlock,
        threshold: Double,
        allBlocks: [ProcessingBlock]
    ) async -> [CandidatePair] {
        var candidates: [CandidatePair] = []
        
        // Process pairs within this block
        for i in 0..<block.elements.count {
            for j in (i+1)..<block.elements.count {
                let element1 = block.elements[i]
                let element2 = block.elements[j]
                
                // Use vectorized similarity check
                if let similarity = await vectorizedSimilarityCheck(
                    element1: element1,
                    element2: element2,
                    matrix: block.matrix,
                    index1: block.startIndex + i,
                    index2: block.startIndex + j,
                    threshold: threshold
                ) {
                    let candidate = CandidatePair(
                        index1: block.startIndex + i,
                        index2: block.startIndex + j,
                        element1: element1,
                        element2: element2,
                        similarity: similarity
                    )
                    candidates.append(candidate)
                }
            }
        }
        
        // Process pairs with other blocks (avoid duplicates)
        for otherBlock in allBlocks {
            guard otherBlock.startIndex > block.startIndex else { continue }
            
            for i in 0..<block.elements.count {
                for j in 0..<otherBlock.elements.count {
                    let element1 = block.elements[i]
                    let element2 = otherBlock.elements[j]
                    
                    if let similarity = await vectorizedSimilarityCheck(
                        element1: element1,
                        element2: element2,
                        matrix: block.matrix,
                        index1: block.startIndex + i,
                        index2: otherBlock.startIndex + j,
                        threshold: threshold
                    ) {
                        let candidate = CandidatePair(
                            index1: block.startIndex + i,
                            index2: otherBlock.startIndex + j,
                            element1: element1,
                            element2: element2,
                            similarity: similarity
                        )
                        candidates.append(candidate)
                    }
                }
            }
        }
        
        return candidates
    }
    
    /// Performs vectorized similarity check using optimized operations
    private func vectorizedSimilarityCheck(
        element1: CodeElement,
        element2: CodeElement,
        matrix: HashMatrix,
        index1: Int,
        index2: Int,
        threshold: Double
    ) async -> Double? {
        // Quick bloom filter precheck
        let fingerprint1 = createFingerprint(from: element1.treeNode)
        let fingerprint2 = createFingerprint(from: element2.treeNode)
        
        // Fast rejection based on basic criteria
        guard fingerprint1.mightBeSimilar(to: fingerprint2, sizeRatioThreshold: threshold * 0.5) else {
            return nil
        }
        
        // Use precomputed hash values for bloom filter check
        let hashes1 = matrix.getHashValues(for: index1)
        let hashes2 = matrix.getHashValues(for: index2)
        
        // Vectorized hash similarity calculation
        let hashSimilarity = calculateVectorizedHashSimilarity(hashes1: hashes1, hashes2: hashes2)
        
        guard hashSimilarity >= threshold * 0.3 else {
            return nil
        }
        
        // If passes all prefilters, calculate actual similarity
        let actualSimilarity = fingerprint1.similarity(to: fingerprint2)
        
        return actualSimilarity >= threshold ? actualSimilarity : nil
    }
    
    /// Calculates hash similarity using vectorized operations
    private func calculateVectorizedHashSimilarity(hashes1: [Int], hashes2: [Int]) -> Double {
        guard hashes1.count == hashes2.count, !hashes1.isEmpty else {
            return 0.0
        }
        
        if configuration.enableSIMD && hashes1.count >= 4 {
            return calculateSIMDHashSimilarity(hashes1: hashes1, hashes2: hashes2)
        } else {
            return calculateStandardHashSimilarity(hashes1: hashes1, hashes2: hashes2)
        }
    }
    
    /// SIMD-optimized hash similarity calculation
    private func calculateSIMDHashSimilarity(hashes1: [Int], hashes2: [Int]) -> Double {
        // For now, use standard calculation - SIMD would require platform-specific implementation
        return calculateStandardHashSimilarity(hashes1: hashes1, hashes2: hashes2)
    }
    
    /// Standard hash similarity calculation
    private func calculateStandardHashSimilarity(hashes1: [Int], hashes2: [Int]) -> Double {
        var matches = 0
        let count = hashes1.count
        
        for i in 0..<count {
            let hash1 = hashes1[i]
            let hash2 = hashes2[i]
            
            // Calculate similarity using bit operations
            let xor = hash1 ^ hash2
            let similarity = 1.0 - (Double(xor.nonzeroBitCount) / 64.0) // Assume 64-bit hashes
            
            if similarity > 0.5 { // Threshold for hash match
                matches += 1
            }
        }
        
        return Double(matches) / Double(count)
    }
    
    /// Reports processing progress
    private func reportProgress(
        blocksProcessed: Int,
        totalBlocks: Int,
        candidatesFound: Int,
        startTime: Double
    ) async {
        guard let progressCallback = configuration.progressCallback else { return }
        
        let currentTime = ProcessInfo.processInfo.systemUptime
        let elapsedTime = currentTime - startTime
        
        let processingRate = elapsedTime > 0 ? Double(blocksProcessed) / elapsedTime : nil
        let estimatedTimeRemaining: Double? = if let rate = processingRate, rate > 0 {
            Double(totalBlocks - blocksProcessed) / rate
        } else {
            nil
        }
        
        let memoryUsage = getMemoryUsage()
        
        let progress = VectorizedProgress(
            blocksProcessed: blocksProcessed,
            totalBlocks: totalBlocks,
            candidatesFound: candidatesFound,
            processingRate: processingRate,
            estimatedTimeRemaining: estimatedTimeRemaining,
            memoryUsage: memoryUsage
        )
        
        progressCallback(progress)
    }
    
    /// Gets current memory pressure (0.0 - 1.0)
    private func getMemoryPressure() -> Double {
        // Simplified memory pressure calculation
        // In a real implementation, this would use system APIs
        return 0.5
    }
    
    /// Gets current memory usage in bytes
    private func getMemoryUsage() -> Int {
        // Simplified memory usage calculation
        // In a real implementation, this would use system APIs
        return 1024 * 1024 // 1MB placeholder
    }
    
    /// Creates an ASTNodeFingerprint from a TreeNode
    private func createFingerprint(from treeNode: TreeNode) -> ASTNodeFingerprint {
        var nodeTypeCounts: [String: Int] = [:]
        var totalNodes = 0
        var maxDepth = 0
        var leafNodeCount = 0
        
        // Traverse the tree to collect statistics
        func traverse(node: TreeNode, depth: Int) {
            totalNodes += 1
            maxDepth = max(maxDepth, depth)
            
            // Count node type
            nodeTypeCounts[node.label, default: 0] += 1
            
            // Check if leaf node
            if node.children.isEmpty {
                leafNodeCount += 1
            }
            
            // Traverse children
            for child in node.children {
                traverse(node: child, depth: depth + 1)
            }
        }
        
        traverse(node: treeNode, depth: 0)
        
        return ASTNodeFingerprint(
            nodeTypeCounts: nodeTypeCounts,
            totalNodes: totalNodes,
            maxDepth: maxDepth,
            leafNodeCount: leafNodeCount
        )
    }
}

// MARK: - Backward Compatibility

extension VectorizedPrefilteringEngine {
    /// Creates a VectorizedPrefilteringEngine with settings compatible with standard PrefilteringEngine
    /// - Parameter standardEngine: The standard prefiltering engine to migrate from
    /// - Returns: Equivalent vectorized prefiltering engine
    public static func from(_ standardEngine: PrefilteringEngine) -> VectorizedPrefilteringEngine {
        // Extract configuration from standard engine if possible
        let configuration = Configuration(optimizationLevel: .balanced)
        return VectorizedPrefilteringEngine(configuration: configuration)
    }
    
    /// Provides a simplified interface matching the original PrefilteringEngine
    /// - Parameters:
    ///   - elements: Code elements to process
    ///   - threshold: Similarity threshold
    /// - Returns: Candidate pairs
    public func prefilter(
        elements: [CodeElement],
        threshold: Double = 0.3
    ) async throws -> [(CodeElement, CodeElement)] {
        let candidates = try await findCandidates(elements: elements, threshold: threshold)
        return candidates.map { ($0.0, $0.1) }
    }
} 