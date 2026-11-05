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
        /// No longer affects scheduling; every level runs the same tasks. Kept for source compatibility.
        public let optimizationLevel: OptimizationLevel
        /// No longer used: work is split into tasks of similar estimated cost. Kept for source compatibility.
        public let blockSize: Int
        /// Maximum number of concurrent tasks (0 = auto-detect)
        public let maxConcurrency: Int
        /// Progress reporting callback
        public let progressCallback: (@Sendable (VectorizedProgress) -> Void)?
        
        public init(
            optimizationLevel: OptimizationLevel = .balanced,
            blockSize: Int = 0,
            maxConcurrency: Int = 0,
            progressCallback: (@Sendable (VectorizedProgress) -> Void)? = nil
        ) {
            self.optimizationLevel = optimizationLevel
            self.blockSize = blockSize
            self.maxConcurrency = maxConcurrency
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
            // Every pair is independent and CPU-bound, so all scales use every core. The level and
            // block size no longer affect scheduling and are kept only for source compatibility.
            switch scale {
            case .small:
                return Configuration(
                    optimizationLevel: .aggressive,
                    blockSize: min(1000, max(100, elementCount / 4)),
                    maxConcurrency: resources.availableCores
                )
            case .medium:
                return Configuration(
                    optimizationLevel: .balanced,
                    blockSize: min(2000, max(500, elementCount / 8)),
                    maxConcurrency: resources.availableCores
                )
            case .large:
                return Configuration(
                    optimizationLevel: .conservative,
                    blockSize: min(5000, max(1000, elementCount / 16)),
                    maxConcurrency: resources.availableCores
                )
            case .massive:
                return Configuration(
                    optimizationLevel: .conservative,
                    blockSize: min(10000, max(2000, elementCount / 32)),
                    maxConcurrency: resources.availableCores
                )
            }
        }
        
        /// Adjust configuration based on runtime performance metrics
        public static func adjust(
            _ configuration: Configuration,
            cpuUtilization: Double,
            processingRate: Double
        ) -> Configuration {
            // If CPU utilization is too high (>80%), reduce parallelism
            guard cpuUtilization > 0.8 else { return configuration }
            return Configuration(
                optimizationLevel: configuration.optimizationLevel,
                blockSize: configuration.blockSize,
                maxConcurrency: max(1, Int(Double(configuration.maxConcurrency) * 0.7)),
                progressCallback: configuration.progressCallback
            )
        }
    }
    
    /// Progress information for vectorized processing
    public struct VectorizedProgress: Sendable {
        public let blocksProcessed: Int
        public let totalBlocks: Int
        public let candidatesFound: Int
        public let processingRate: Double? // blocks per second
        public let estimatedTimeRemaining: Double? // seconds
        
        public var completionPercentage: Double {
            return totalBlocks > 0 ? Double(blocksProcessed) / Double(totalBlocks) * 100.0 : 0.0
        }
    }
    
    // MARK: - Internal Types
    
    /// Pairs of one element (`order[row]`) with the elements at `positions` in the processing order
    struct PairTask: Sendable, Equatable {
        let row: Int
        let positions: Range<Int>
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
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
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
        var fingerprintList: [ASTNodeFingerprint] = []
        for (index, element) in elements.enumerated() {
            fingerprintList.append(element.treeNode.extractFingerprint())
            
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
        
        let fingerprints = fingerprintList
        
        // Element order[p] is compared with every element after it in `order`. Elements are ordered
        // by size, largest first, and each such row is cut into tasks of roughly equal estimated cost
        // (product of the tree sizes, the shape of the edit distance cost). Tasks are submitted
        // heaviest first, so one large pair does not keep a long run of other work on a single core.
        let order = elements.indices.sorted { fingerprints[$0].totalNodes > fingerprints[$1].totalNodes }
        let maxConcurrency = configuration.maxConcurrency > 0
            ? configuration.maxConcurrency
            : ProcessInfo.processInfo.processorCount
        let tasks = Self.makeTasks(sizes: order.map { fingerprints[$0].totalNodes }, workerCount: maxConcurrency)
        
        await reportProgress(blocksProcessed: 0, totalBlocks: tasks.count, candidatesFound: 0, startTime: startTime)
        
        var candidates: [CandidatePair] = []
        try await withThrowingTaskGroup(of: [CandidatePair].self) { group in
            var nextTask = 0
            func submitNext() {
                guard nextTask < tasks.count else { return }
                let task = tasks[nextTask]
                nextTask += 1
                group.addTask {
                    self.process(task, order: order, elements: elements, fingerprints: fingerprints, threshold: threshold)
                }
            }
            for _ in 0..<maxConcurrency { submitNext() }
            
            var processedTasks = 0
            for try await taskCandidates in group {
                candidates.append(contentsOf: taskCandidates)
                processedTasks += 1
                await reportProgress(blocksProcessed: processedTasks, totalBlocks: tasks.count, candidatesFound: candidates.count, startTime: startTime)
                submitNext()
            }
        }
        
        // Completion order varies between runs; return a stable order instead: most similar first,
        // ties by position in `elements`.
        candidates.sort {
            ($0.similarity, $1.index1, $1.index2) > ($1.similarity, $0.index1, $0.index2)
        }
        return candidates.map { ($0.element1, $0.element2, $0.similarity) }
    }
    
    // MARK: - Private Implementation
    
    /// Compares element `order[task.row]` with the elements at `task.positions` in `order`.
    /// Pairs are reported in input order (lower index first).
    private func process(
        _ task: PairTask,
        order: [Int],
        elements: [CodeElement],
        fingerprints: [ASTNodeFingerprint],
        threshold: Double
    ) -> [CandidatePair] {
        var candidates: [CandidatePair] = []
        let first = order[task.row]
        for position in task.positions {
            let second = order[position]
            let (index1, index2) = first < second ? (first, second) : (second, first)
            if let similarity = similarityCheck(
                element1: elements[index1],
                element2: elements[index2],
                fingerprints: fingerprints,
                index1: index1,
                index2: index2,
                threshold: threshold
            ) {
                candidates.append(CandidatePair(
                    index1: index1,
                    index2: index2,
                    element1: elements[index1],
                    element2: elements[index2],
                    similarity: similarity
                ))
            }
        }
        return candidates
    }
    
    /// Splits all pairs into tasks of roughly equal estimated cost.
    /// - Parameters:
    ///   - sizes: Tree sizes in processing order (largest first)
    ///   - workerCount: Number of tasks run concurrently
    /// - Returns: Tasks covering every pair `(row, position)` with `row < position` exactly once,
    ///   roughly heaviest first
    static func makeTasks(sizes: [Int], workerCount: Int) -> [PairTask] {
        guard sizes.count >= 2 else { return [] }
        // Suffix sums give each row's cost without visiting every pair.
        var suffix = [Double](repeating: 0, count: sizes.count + 1)
        for index in stride(from: sizes.count - 1, through: 0, by: -1) {
            suffix[index] = suffix[index + 1] + Double(sizes[index])
        }
        var totalCost = 0.0
        for row in 0..<(sizes.count - 1) {
            totalCost += Double(sizes[row]) * suffix[row + 1]
        }
        // Many more tasks than workers, so the last ones to finish are small.
        let budget = max(totalCost / Double(max(1, workerCount) * 32), 1)
        
        var tasks: [PairTask] = []
        for row in 0..<(sizes.count - 1) {
            let rowSize = Double(sizes[row])
            if rowSize * suffix[row + 1] <= budget {
                tasks.append(PairTask(row: row, positions: (row + 1)..<sizes.count))
                continue
            }
            var start = row + 1
            var cost = 0.0
            for position in (row + 1)..<sizes.count {
                cost += rowSize * Double(sizes[position])
                if cost >= budget {
                    tasks.append(PairTask(row: row, positions: start..<(position + 1)))
                    start = position + 1
                    cost = 0
                }
            }
            if start < sizes.count {
                tasks.append(PairTask(row: row, positions: start..<sizes.count))
            }
        }
        return tasks
    }
    
    /// TSED score of the pair if it reaches `threshold`, skipping pairs the exact bounds rule out
    private func similarityCheck(
        element1: CodeElement,
        element2: CodeElement,
        fingerprints: [ASTNodeFingerprint],
        index1: Int,
        index2: Int,
        threshold: Double
    ) -> Double? {
        // A declaration and one nested inside it share code; never report them as similar.
        guard !element1.isNested(with: element2) else {
            return nil
        }
        
        // Exact prefilter: skip pairs whose TSED upper bound (from label histograms) is below
        // the threshold. Unlike heuristic filters this never rejects a pair that would match.
        let fingerprint1 = fingerprints[index1]
        let fingerprint2 = fingerprints[index2]
        guard fingerprint1.tsedUpperBound(to: fingerprint2) >= threshold else {
            return nil
        }
        
        // TSED: tree edit distance normalized by the larger tree size
        // (skipped when a cheaper exact lower bound already rules the pair out)
        return SimilarityCalculator()
            .similarity(between: element1.treeNode, and: element2.treeNode, atLeast: threshold)
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
        
        let progress = VectorizedProgress(
            blocksProcessed: blocksProcessed,
            totalBlocks: totalBlocks,
            candidatesFound: candidatesFound,
            processingRate: processingRate,
            estimatedTimeRemaining: estimatedTimeRemaining
        )
        
        progressCallback(progress)
    }
}
