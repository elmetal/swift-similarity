import Foundation

// MARK: - Scan Statistics

/// Pair counts and timings of a `SimilarityScanner` scan, reported by `scan --stats`.
///
/// Every pair is accounted for once:
/// `totalPairs == nestedPairs + pairsRuledOutByUpperBound + pairsCompared + identicalPairs`.
///
/// Elements with identical trees are compared once per class (see `SimilarityScanner`), but each
/// pair is still counted under the step that decided it.
public struct ScanStatistics: Sendable, Equatable {
    /// Number of elements scanned
    public let elementCount: Int
    /// Number of pairs of elements
    public let totalPairs: Int
    /// Pairs skipped because one declaration is nested inside the other
    public let nestedPairs: Int
    /// Pairs skipped because the TSED upper bound from the label histograms is below the threshold
    public let pairsRuledOutByUpperBound: Int
    /// Pairs passed to the bounded TSED computation
    public let pairsCompared: Int
    /// Pairs whose TSED score reached the threshold
    public let similarPairs: Int
    /// Number of tasks run concurrently
    public let workerCount: Int
    /// Seconds spent computing fingerprints
    public let fingerprintTime: Double
    /// Seconds spent comparing pairs, including sorting the results
    public let comparisonTime: Double
    /// Number of distinct trees: elements with identical trees count once
    public let distinctTreeCount: Int
    /// Pairs of elements with identical trees, which score 1.0 without a comparison
    public let identicalPairs: Int

    public init(
        elementCount: Int,
        totalPairs: Int,
        nestedPairs: Int,
        pairsRuledOutByUpperBound: Int,
        pairsCompared: Int,
        similarPairs: Int,
        workerCount: Int,
        fingerprintTime: Double,
        comparisonTime: Double,
        distinctTreeCount: Int? = nil,
        identicalPairs: Int = 0
    ) {
        self.elementCount = elementCount
        self.totalPairs = totalPairs
        self.nestedPairs = nestedPairs
        self.pairsRuledOutByUpperBound = pairsRuledOutByUpperBound
        self.pairsCompared = pairsCompared
        self.similarPairs = similarPairs
        self.workerCount = workerCount
        self.fingerprintTime = fingerprintTime
        self.comparisonTime = comparisonTime
        self.distinctTreeCount = distinctTreeCount ?? elementCount
        self.identicalPairs = identicalPairs
    }

    /// Seconds for the whole scan
    public var totalTime: Double { fingerprintTime + comparisonTime }

    /// Share of pairs (0.0-1.0) that never reached the TSED computation
    public var skippedRatio: Double {
        totalPairs > 0 ? 1.0 - Double(pairsCompared) / Double(totalPairs) : 0.0
    }
}
