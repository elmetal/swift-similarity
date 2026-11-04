import Foundation

// MARK: - Hierarchical Processing Pipeline (Phase 11)

/// High-performance hierarchical processing system for massive similarity detection
/// Target: 5-20x speedup through progressive filtering stages
public final class HierarchicalProcessor: Sendable {
    
    // MARK: - Configuration
    
    /// Processing stage configuration
    public struct Configuration: Sendable {
        /// Stage 1: Quick filtering threshold offset (+0.2 from target)
        public let quickStageOffset: Double
        /// Stage 2: Medium filtering threshold offset (+0.1 from target)
        public let mediumStageOffset: Double
        /// Maximum candidates to pass to next stage (0 = unlimited).
        /// Lossy: once the limit is reached, the remaining pairs are not compared at all.
        public let maxCandidatesPerStage: Int
        /// Enable statistical sampling for massive datasets.
        /// Lossy and non-deterministic: a random subset of elements is discarded before comparison.
        public let enableSampling: Bool
        /// Sampling ratio for initial stage (0.0-1.0)
        public let samplingRatio: Double
        /// Enable early termination when enough results found
        public let enableEarlyTermination: Bool
        /// Target result count for early termination (0 = disabled)
        public let targetResultCount: Int
        
        public init(
            quickStageOffset: Double = 0.2,
            mediumStageOffset: Double = 0.1,
            maxCandidatesPerStage: Int = 0,
            enableSampling: Bool = false,
            samplingRatio: Double = 0.8,
            enableEarlyTermination: Bool = true,
            targetResultCount: Int = 1000
        ) {
            self.quickStageOffset = quickStageOffset
            self.mediumStageOffset = mediumStageOffset
            self.maxCandidatesPerStage = maxCandidatesPerStage
            self.enableSampling = enableSampling
            self.samplingRatio = samplingRatio
            self.enableEarlyTermination = enableEarlyTermination
            self.targetResultCount = targetResultCount
        }
        
        /// Optimal configuration for different project scales.
        /// None of the presets sample elements or cap candidates, so no similar pair is dropped.
        public static func optimal(for scale: VectorizedPrefilteringEngine.AdaptiveConfiguration.ProjectScale) -> Configuration {
            switch scale {
            case .small:
                return Configuration(
                    quickStageOffset: -0.2, // More permissive for Stage 1
                    mediumStageOffset: 0.0,  // Use exact threshold for Stage 2
                    maxCandidatesPerStage: 0,
                    enableSampling: false,
                    enableEarlyTermination: false
                )
            case .medium:
                return Configuration(
                    quickStageOffset: 0.2,
                    mediumStageOffset: 0.1,
                    maxCandidatesPerStage: 0,
                    enableSampling: false,
                    enableEarlyTermination: true,
                    targetResultCount: 2000
                )
            case .large:
                return Configuration(
                    quickStageOffset: 0.15,  // Fixed: 0.7 + 0.15 = 0.85 (reasonable)
                    mediumStageOffset: 0.08,  // Fixed: 0.7 + 0.08 = 0.78 (reasonable)
                    maxCandidatesPerStage: 0,
                    enableSampling: false,
                    enableEarlyTermination: true,
                    targetResultCount: 1200  // Increased from 1000
                )
            case .massive:
                return Configuration(
                    quickStageOffset: 0.15,  // Fixed: 0.7 + 0.15 = 0.85 (reasonable)
                    mediumStageOffset: 0.08,  // Fixed: 0.7 + 0.08 = 0.78 (reasonable)
                    maxCandidatesPerStage: 0,
                    enableSampling: false,
                    enableEarlyTermination: true,
                    targetResultCount: 800  // Increased from 500
                )
            }
        }
    }
    
    /// Progress information for hierarchical processing
    public struct HierarchicalProgress: Sendable {
        /// Current processing stage (1-3)
        public let currentStage: Int
        /// Stage name
        public let stageName: String
        /// Elements processed in current stage
        public let elementsProcessed: Int
        /// Total elements in current stage
        public let totalElements: Int
        /// Candidates found in current stage
        public let candidatesFound: Int
        /// Reduction ratio achieved so far
        public let reductionRatio: Double
        /// Estimated time remaining
        public let estimatedTimeRemaining: Double?
        
        public init(
            currentStage: Int,
            stageName: String,
            elementsProcessed: Int,
            totalElements: Int,
            candidatesFound: Int,
            reductionRatio: Double,
            estimatedTimeRemaining: Double? = nil
        ) {
            self.currentStage = currentStage
            self.stageName = stageName
            self.elementsProcessed = elementsProcessed
            self.totalElements = totalElements
            self.candidatesFound = candidatesFound
            self.reductionRatio = reductionRatio
            self.estimatedTimeRemaining = estimatedTimeRemaining
        }
    }
    
    /// Processing statistics for each stage
    public struct StageStatistics: Sendable {
        /// Stage number
        public let stage: Int
        /// Stage name
        public let name: String
        /// Processing time in seconds
        public let processingTime: Double
        /// Input candidates count
        public let inputCandidates: Int
        /// Output candidates count
        public let outputCandidates: Int
        /// Reduction ratio achieved
        public let reductionRatio: Double
        /// Processing rate (candidates/second)
        public let processingRate: Double
        
        public init(stage: Int, name: String, processingTime: Double, inputCandidates: Int, outputCandidates: Int) {
            self.stage = stage
            self.name = name
            self.processingTime = processingTime
            self.inputCandidates = inputCandidates
            self.outputCandidates = outputCandidates
            self.reductionRatio = inputCandidates > 0 ? Double(inputCandidates - outputCandidates) / Double(inputCandidates) : 0.0
            self.processingRate = processingTime > 0 ? Double(inputCandidates) / processingTime : 0.0
        }
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private let vectorizedEngine: VectorizedPrefilteringEngine
    private let progressCallback: (@Sendable (HierarchicalProgress) -> Void)?
    
    // MARK: - Initialization
    
    public init(
        configuration: Configuration,
        vectorizedConfig: VectorizedPrefilteringEngine.Configuration? = nil,
        progressCallback: (@Sendable (HierarchicalProgress) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.progressCallback = progressCallback
        
        // Create optimized vectorized engine for each stage
        let engineConfig = vectorizedConfig ?? VectorizedPrefilteringEngine.Configuration(
            optimizationLevel: .aggressive,
            blockSize: 2000,
            maxConcurrency: 4, // Conservative for stage processing
            enableSIMD: true
        )
        self.vectorizedEngine = VectorizedPrefilteringEngine(configuration: engineConfig)
    }
    
    // MARK: - Main Processing Method
    
    /// Process elements through hierarchical pipeline
    public func process(
        elements: [CodeElement],
        threshold: Double
    ) async throws -> ([(CodeElement, CodeElement, Double)], [StageStatistics]) {
        
        let stage1StartTime = ProcessInfo.processInfo.systemUptime
        var statistics: [StageStatistics] = []
        
        // Report preparation stage progress
        reportProgress(stage: 1, stageName: "Preparing", elementsProcessed: 0, totalElements: elements.count, candidatesFound: 0, reductionRatio: 0.0)
        
        // Create fingerprints with progress reporting (this is the heavy operation)
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
                reportProgress(stage: 1, stageName: "Creating Fingerprints", elementsProcessed: index + 1, totalElements: elements.count, candidatesFound: 0, reductionRatio: 0.0)
            }
        }
        
        // Apply sampling if enabled for massive datasets
        let sampledElements = applySampling(elements: elements)
        let _ = sampledElements.count * (sampledElements.count - 1) / 2 // totalPossiblePairs - unused
        
        // Create Stage 1 statistics
        let stage1EndTime = ProcessInfo.processInfo.systemUptime
        let stage1Statistics = StageStatistics(
            stage: 1,
            name: "Preparation & Fingerprinting",
            processingTime: stage1EndTime - stage1StartTime,
            inputCandidates: elements.count,
            outputCandidates: sampledElements.count
        )
        statistics.append(stage1Statistics)
        
        // Stage 2: Ultra-fast fingerprint-only comparison
        let stage1Results = try await stage1QuickFilter(
            elements: sampledElements,
            // The stage 1 filter is an exact TSED upper bound, so it must use the target threshold:
            // a stricter threshold would drop pairs that the final stage would accept.
            threshold: threshold,
            stageStartTime: ProcessInfo.processInfo.systemUptime
        )
        statistics.append(stage1Results.statistics)
        
        // Early termination check
        if shouldTerminateEarly(candidateCount: stage1Results.candidates.count) {
            let finalResults = try await stage2DirectAPTEDCalculation(
                candidates: stage1Results.candidates,
                threshold: threshold,
                stageStartTime: ProcessInfo.processInfo.systemUptime
            )
            statistics.append(finalResults.statistics)
            return (finalResults.results, statistics)
        }
        
        // Simplified Stage 2: Direct APTED calculation (same as standard processing)
        let stage2Results = try await stage2DirectAPTEDCalculation(
            candidates: stage1Results.candidates,
            threshold: threshold,
            stageStartTime: ProcessInfo.processInfo.systemUptime
        )
        statistics.append(stage2Results.statistics)
        
        return (stage2Results.results, statistics)
    }
    
    // MARK: - Stage Implementations
    
    /// Stage 1: Ultra-fast fingerprint-only comparison
    private func stage1QuickFilter(
        elements: [CodeElement],
        threshold: Double,
        stageStartTime: Double
    ) async throws -> (candidates: [(CodeElement, CodeElement)], statistics: StageStatistics) {
        
        reportProgress(stage: 2, stageName: "Quick Filter", elementsProcessed: 0, totalElements: elements.count, candidatesFound: 0, reductionRatio: 0.0)
        
        var candidates: [(CodeElement, CodeElement)] = []
        let totalPairs = elements.count * (elements.count - 1) / 2
        var processedPairs = 0
        let fingerprints = elements.map { createFingerprint(from: $0.treeNode) }
        
        // Reject pairs whose TSED upper bound is below the threshold (no false negatives)
        for i in 0..<elements.count {
            for j in (i+1)..<elements.count {
                let element1 = elements[i]
                let element2 = elements[j]
                
                processedPairs += 1
                guard fingerprints[i].tsedUpperBound(to: fingerprints[j]) >= threshold else {
                    continue
                }
                candidates.append((element1, element2))
                
                // Check max candidates limit (0 means no limit)
                if configuration.maxCandidatesPerStage > 0 && candidates.count >= configuration.maxCandidatesPerStage {
                    break
                }
                
                // Report progress periodically
                if processedPairs % 10000 == 0 {
                    let reductionRatio = totalPairs > 0 ? Double(totalPairs - candidates.count) / Double(totalPairs) : 0.0
                    reportProgress(stage: 2, stageName: "Quick Filter", elementsProcessed: processedPairs, totalElements: totalPairs, candidatesFound: candidates.count, reductionRatio: reductionRatio)
                }
            }
            
            if configuration.maxCandidatesPerStage > 0 && candidates.count >= configuration.maxCandidatesPerStage {
                break
            }
        }
        
        let endTime = ProcessInfo.processInfo.systemUptime
        let processingTime = endTime - stageStartTime
        let finalReductionRatio = totalPairs > 0 ? Double(totalPairs - candidates.count) / Double(totalPairs) : 0.0
        
        reportProgress(stage: 2, stageName: "Quick Filter", elementsProcessed: totalPairs, totalElements: totalPairs, candidatesFound: candidates.count, reductionRatio: finalReductionRatio)
        
        let statistics = StageStatistics(
            stage: 2,
            name: "Quick Filter",
            processingTime: processingTime,
            inputCandidates: totalPairs,
            outputCandidates: candidates.count
        )
        
        return (candidates, statistics)
    }
    

    
    /// Stage 2: Direct APTED calculation (simplified hierarchical processing)
    private func stage2DirectAPTEDCalculation(
        candidates: [(CodeElement, CodeElement)],
        threshold: Double,
        stageStartTime: Double
    ) async throws -> (results: [(CodeElement, CodeElement, Double)], statistics: StageStatistics) {
        
        reportProgress(stage: 3, stageName: "Direct APTED", elementsProcessed: 0, totalElements: candidates.count, candidatesFound: 0, reductionRatio: 0.0)
        
        var results: [(CodeElement, CodeElement, Double)] = []
        
        for (index, (element1, element2)) in candidates.enumerated() {
            // Calculate full APTED similarity using the same method as standard processing
            let similarity = try calculatePreciseSimilarity(element1, element2)
            
            // Apply threshold check
            
            if similarity >= threshold {
                results.append((element1, element2, similarity))
            }
            
            // Report progress periodically
            if index % 100 == 0 {
                let reductionRatio = candidates.count > 0 ? Double(candidates.count - results.count) / Double(candidates.count) : 0.0
                reportProgress(stage: 3, stageName: "Direct APTED", elementsProcessed: index, totalElements: candidates.count, candidatesFound: results.count, reductionRatio: reductionRatio)
            }
        }
        
        let endTime = ProcessInfo.processInfo.systemUptime
        let processingTime = endTime - stageStartTime
        let finalReductionRatio = candidates.count > 0 ? Double(candidates.count - results.count) / Double(candidates.count) : 0.0
        
        reportProgress(stage: 3, stageName: "Direct APTED", elementsProcessed: candidates.count, totalElements: candidates.count, candidatesFound: results.count, reductionRatio: finalReductionRatio)
        
        let statistics = StageStatistics(
            stage: 3,
            name: "Direct APTED",
            processingTime: processingTime,
            inputCandidates: candidates.count,
            outputCandidates: results.count
        )
        
        return (results, statistics)
    }
    

    
    // MARK: - Helper Methods
    
    /// Apply statistical sampling for massive datasets
    private func applySampling(elements: [CodeElement]) -> [CodeElement] {
        guard configuration.enableSampling && elements.count > 1000 else {
            return elements
        }
        
        let sampleSize = Int(Double(elements.count) * configuration.samplingRatio)
        return Array(elements.shuffled().prefix(sampleSize))
    }
    
    /// Check if early termination should be applied
    private func shouldTerminateEarly(candidateCount: Int) -> Bool {
        return configuration.enableEarlyTermination &&
               configuration.targetResultCount > 0 &&
               candidateCount <= configuration.targetResultCount
    }
    
    /// Create fingerprint from tree node
    private func createFingerprint(from treeNode: TreeNode) -> ASTNodeFingerprint {
        var nodeTypeCounts: [String: Int] = [:]
        var totalNodes = 0
        var maxDepth = 0
        var leafNodeCount = 0
        
        func traverse(node: TreeNode, depth: Int) {
            totalNodes += 1
            maxDepth = max(maxDepth, depth)
            
            let nodeType = node.label
            nodeTypeCounts[nodeType, default: 0] += 1
            
            if node.children.isEmpty {
                leafNodeCount += 1
            }
            
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
    

    

    
    /// Calculate similarity using the same method as standard processing (VectorizedPrefilteringEngine)
    private func calculatePreciseSimilarity(_ element1: CodeElement, _ element2: CodeElement) throws -> Double {
        // TSED: tree edit distance normalized by the larger tree size
        return SimilarityCalculator()
            .calculateSimilarity(between: element1.treeNode, and: element2.treeNode)
            .similarityScore
    }
    
    /// Report processing progress
    private func reportProgress(
        stage: Int,
        stageName: String,
        elementsProcessed: Int,
        totalElements: Int,
        candidatesFound: Int,
        reductionRatio: Double,
        estimatedTimeRemaining: Double? = nil
    ) {
        let progress = HierarchicalProgress(
            currentStage: stage,
            stageName: stageName,
            elementsProcessed: elementsProcessed,
            totalElements: totalElements,
            candidatesFound: candidatesFound,
            reductionRatio: reductionRatio,
            estimatedTimeRemaining: estimatedTimeRemaining
        )
        
        progressCallback?(progress)
    }
} 