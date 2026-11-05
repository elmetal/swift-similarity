import Foundation

// MARK: - Similarity Scanner

/// Finds every pair of code elements whose TSED score reaches a threshold.
///
/// The pipeline is exact: it reports the same pairs, with the same scores, as comparing every pair
/// with `SimilarityCalculator`.
/// 1. Each element's tree is prepared once (`PreparedTree`): label histogram, size, and what the
///    tree edit distance and its lower bounds need, with labels interned to integers.
/// 2. Pairs of a declaration and one nested inside it are skipped.
/// 3. Pairs whose TSED upper bound (from the histograms) is below the threshold are skipped.
/// 4. The remaining pairs get a bounded TSED computation, in parallel on every core.
/// 5. Results are sorted by score, highest first, ties in input order.
public struct SimilarityScanner: Sendable {

    // MARK: - Types

    /// A pair of elements and their TSED score. `first` comes before `second` in the input.
    public typealias Pair = (first: CodeElement, second: CodeElement, similarity: Double)

    /// Progress of a scan, reported through the scanner's progress handler.
    public struct Progress: Sendable {
        /// The step a scan is in
        public enum Phase: String, Sendable {
            /// Preparing each element's tree (label histogram and edit distance indexes); units are elements
            case fingerprinting
            /// Comparing pairs; units are tasks (groups of pairs of similar estimated cost)
            case comparing
        }

        public let phase: Phase
        /// Units of the current phase that are done
        public let completed: Int
        /// Units in the current phase
        public let total: Int
        /// Similar pairs found so far
        public let pairsFound: Int
        /// Estimated seconds until the current phase is done, from the rate so far
        public let estimatedTimeRemaining: Double?

        /// Completion of the current phase, from 0 to 100
        public var completionPercentage: Double {
            total > 0 ? Double(completed) / Double(total) * 100.0 : 0.0
        }
    }

    /// What a scan found and how much work the filters saved.
    public struct Result: Sendable {
        /// Similar pairs, highest score first, ties in input order
        public let pairs: [Pair]
        /// Pair counts and timings
        public let statistics: ScanStatistics
    }

    // MARK: - Properties

    /// Maximum number of concurrent tasks (0 = number of cores)
    public let maxConcurrency: Int
    /// Called with progress information, from any thread
    public let progressHandler: (@Sendable (Progress) -> Void)?
    /// Tree edit operation costs, used for TSED and for both of its exact bounds
    public let costs: APTED.OperationCosts

    /// Number of tasks a scan runs concurrently
    public var workerCount: Int {
        maxConcurrency > 0 ? maxConcurrency : ProcessInfo.processInfo.processorCount
    }

    // MARK: - Initialization

    /// - Parameters:
    ///   - maxConcurrency: Maximum number of concurrent tasks (0 = number of cores)
    ///   - progressHandler: Called with progress information, from any thread
    ///   - costs: Tree edit operation costs (default: unit costs, as in the TSED paper)
    public init(
        maxConcurrency: Int = 0,
        progressHandler: (@Sendable (Progress) -> Void)? = nil,
        costs: APTED.OperationCosts = APTED.OperationCosts()
    ) {
        self.maxConcurrency = maxConcurrency
        self.progressHandler = progressHandler
        self.costs = costs
    }

    // MARK: - Public Interface

    /// Finds every pair of `elements` whose TSED score is at least `threshold`.
    public func scan(_ elements: [CodeElement], threshold: Double) async throws -> Result {
        let startTime = ProcessInfo.processInfo.systemUptime
        let trees = prepare(elements, startTime: startTime)
        let fingerprintTime = ProcessInfo.processInfo.systemUptime - startTime

        let workerCount = workerCount
        var counts = PairCounts()
        var pairs: [IndexedPair] = []

        if elements.count >= 2 {
            // Element order[p] is compared with every element after it in `order`. Elements are
            // ordered by size, largest first, and each such row is cut into tasks of roughly equal
            // estimated cost (product of the tree sizes, the shape of the edit distance cost). Tasks
            // are submitted heaviest first, so one large pair does not keep a long run of other work
            // on a single core.
            let order = elements.indices.sorted { trees[$0].nodeCount > trees[$1].nodeCount }
            let tasks = Self.makeTasks(sizes: order.map { trees[$0].nodeCount }, workerCount: workerCount)
            let comparisonStart = ProcessInfo.processInfo.systemUptime
            report(.comparing, completed: 0, total: tasks.count, pairsFound: 0, since: comparisonStart)

            try await withThrowingTaskGroup(of: TaskResult.self) { group in
                var nextTask = 0
                func submitNext() {
                    guard nextTask < tasks.count else { return }
                    let task = tasks[nextTask]
                    nextTask += 1
                    let costs = costs
                    group.addTask {
                        Self.compare(task, order: order, elements: elements, trees: trees, threshold: threshold, costs: costs)
                    }
                }
                for _ in 0..<workerCount { submitNext() }

                var completedTasks = 0
                for try await result in group {
                    pairs.append(contentsOf: result.pairs)
                    counts.add(result.counts)
                    completedTasks += 1
                    report(.comparing, completed: completedTasks, total: tasks.count, pairsFound: pairs.count, since: comparisonStart)
                    submitNext()
                }
            }
        }

        // Completion order varies between runs; return a stable order instead: most similar first,
        // ties by position in `elements`.
        pairs.sort {
            ($0.similarity, $1.index1, $1.index2) > ($1.similarity, $0.index1, $0.index2)
        }

        let totalTime = ProcessInfo.processInfo.systemUptime - startTime
        let statistics = ScanStatistics(
            elementCount: elements.count,
            totalPairs: elements.count * max(0, elements.count - 1) / 2,
            nestedPairs: counts.nested,
            pairsRuledOutByUpperBound: counts.ruledOutByUpperBound,
            pairsCompared: counts.compared,
            similarPairs: pairs.count,
            workerCount: workerCount,
            fingerprintTime: fingerprintTime,
            comparisonTime: totalTime - fingerprintTime
        )
        return Result(
            pairs: pairs.map { (elements[$0.index1], elements[$0.index2], $0.similarity) },
            statistics: statistics
        )
    }

    /// Finds every pair of `elements` whose TSED score is at least `threshold`, highest score first.
    public func findSimilarPairs(in elements: [CodeElement], threshold: Double) async throws -> [Pair] {
        try await scan(elements, threshold: threshold).pairs
    }

    // MARK: - Pair Tasks

    /// Pairs of one element (`order[row]`) with the elements at `positions` in the processing order
    struct PairTask: Sendable, Equatable {
        let row: Int
        let positions: Range<Int>
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

    // MARK: - Private Implementation

    /// A similar pair, by position in the input (`index1 < index2`)
    private struct IndexedPair: Sendable {
        let index1: Int
        let index2: Int
        let similarity: Double
    }

    /// How many pairs each step skipped or compared
    private struct PairCounts: Sendable {
        var nested = 0
        var ruledOutByUpperBound = 0
        var compared = 0

        mutating func add(_ other: PairCounts) {
            nested += other.nested
            ruledOutByUpperBound += other.ruledOutByUpperBound
            compared += other.compared
        }
    }

    private struct TaskResult: Sendable {
        let pairs: [IndexedPair]
        let counts: PairCounts
    }

    /// Prepares every element's tree on all cores. Only mapping each tree's distinct labels to
    /// scan-wide ids runs sequentially.
    private func prepare(_ elements: [CodeElement], startTime: Double) -> [PreparedTree] {
        let flatTrees = elements.concurrentMap { FlatTree($0.treeNode) }
        var labels = LabelInterner()
        let labelIds = flatTrees.map { $0.labels.map { labels.id(for: $0) } }
        let trees = Array(zip(flatTrees, labelIds)).concurrentMap { PreparedTree($0, labelIds: $1) }
        report(.fingerprinting, completed: elements.count, total: elements.count, pairsFound: 0, since: startTime)
        return trees
    }

    /// Compares element `order[task.row]` with the elements at `task.positions` in `order`.
    private static func compare(
        _ task: PairTask,
        order: [Int],
        elements: [CodeElement],
        trees: [PreparedTree],
        threshold: Double,
        costs: APTED.OperationCosts
    ) -> TaskResult {
        let calculator = SimilarityCalculator(configuration: .init(aptedCosts: costs))
        var pairs: [IndexedPair] = []
        var counts = PairCounts()
        let first = order[task.row]
        for position in task.positions {
            let second = order[position]
            let (index1, index2) = first < second ? (first, second) : (second, first)

            // A declaration and one nested inside it share code; never report them as similar.
            guard !elements[index1].isNested(with: elements[index2]) else {
                counts.nested += 1
                continue
            }
            // Exact prefilter: the TSED upper bound from label histograms. Unlike heuristic
            // filters this never rejects a pair that would match.
            guard trees[index1].tsedUpperBound(to: trees[index2], costs: costs) >= threshold else {
                counts.ruledOutByUpperBound += 1
                continue
            }
            // TSED: tree edit distance normalized by the larger tree size (skipped when a cheaper
            // exact lower bound on the distance already rules the pair out)
            counts.compared += 1
            if let similarity = calculator.similarity(
                between: trees[index1],
                and: trees[index2],
                atLeast: threshold
            ) {
                pairs.append(IndexedPair(index1: index1, index2: index2, similarity: similarity))
            }
        }
        return TaskResult(pairs: pairs, counts: counts)
    }

    private func report(_ phase: Progress.Phase, completed: Int, total: Int, pairsFound: Int, since startTime: Double) {
        guard let progressHandler else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        let rate = elapsed > 0 ? Double(completed) / elapsed : 0
        progressHandler(Progress(
            phase: phase,
            completed: completed,
            total: total,
            pairsFound: pairsFound,
            estimatedTimeRemaining: rate > 0 ? Double(total - completed) / rate : nil
        ))
    }
}
