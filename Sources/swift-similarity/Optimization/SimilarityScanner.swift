import Foundation

// MARK: - Similarity Scanner

/// Finds every pair of code elements whose TSED score reaches a threshold.
///
/// The pipeline is exact: it reports the same pairs, with the same scores, as comparing every pair
/// with `SimilarityCalculator`.
/// 1. Each element's tree is prepared once (`PreparedTree`): label histogram, size, and what the
///    tree edit distance and its lower bounds need, with labels interned to integers.
/// 2. Elements with identical trees form one class (copies, typical of generated code). Copies
///    score 1.0 with each other, and every copy has the same score with any other tree, so only
///    one tree per class (its first element) is compared below. The scores stay exact.
/// 3. Pairs of a declaration and one nested inside it are skipped.
/// 4. Pairs whose TSED upper bound (from the histograms) is below the threshold are skipped.
/// 5. The remaining pairs get a bounded TSED computation, in parallel on every core.
/// 6. Results are sorted by score, highest first, ties in input order. With `maxPairs`, only the
///    first pairs are kept, in memory proportional to that limit, however many pairs match.
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
        /// Similar pairs, highest score first, ties in input order; at most `maxPairs` of them
        public let pairs: [Pair]
        /// Pair counts and timings
        public let statistics: ScanStatistics
        /// Similar pairs accepted by the scan's `including` predicate, including those left out of
        /// `pairs` because of `maxPairs`
        public let matchingPairCount: Int

        public init(pairs: [Pair], statistics: ScanStatistics, matchingPairCount: Int? = nil) {
            self.pairs = pairs
            self.statistics = statistics
            self.matchingPairCount = matchingPairCount ?? pairs.count
        }

        /// Matching pairs left out because of `maxPairs`
        public var omittedPairCount: Int { matchingPairCount - pairs.count }
    }

    /// Whether a similar pair is reported (see `scan(_:threshold:maxPairs:including:)`).
    public typealias PairPredicate = @Sendable (CodeElement, CodeElement) -> Bool

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
    /// - Parameters:
    ///   - maxPairs: Keep only this many pairs (the most similar, ties in input order); nil keeps
    ///     all. `Result.matchingPairCount` still counts every matching pair.
    ///   - include: Only pairs it accepts are reported and count as matching; nil accepts all.
    ///     Applied before `maxPairs`, so the limit counts reported pairs only.
    public func scan(
        _ elements: [CodeElement],
        threshold: Double,
        maxPairs: Int? = nil,
        including include: PairPredicate? = nil
    ) async throws -> Result {
        let startTime = ProcessInfo.processInfo.systemUptime
        let trees = prepare(elements, startTime: startTime)
        let classes = Self.identicalClasses(trees)
        let fingerprintTime = ProcessInfo.processInfo.systemUptime - startTime

        let workerCount = workerCount
        var counts = PairCounts()
        var blocks: [Block] = []

        // Copies of each other: identical trees score 1.0.
        for (index, members) in classes.enumerated() where members.count >= 2 {
            var identical = 0
            for a in 0..<members.count {
                for b in (a + 1)..<members.count {
                    if elements[members[a]].isNested(with: elements[members[b]]) {
                        counts.nested += 1
                    } else {
                        identical += 1
                    }
                }
            }
            counts.identical += identical
            if identical > 0 {
                blocks.append(Block(similarity: 1.0, class1: index, class2: index))
            }
        }

        if classes.count >= 2 {
            // Class order[p] is compared with every class after it in `order`. Classes are
            // ordered by tree size, largest first, and each such row is cut into tasks of roughly
            // equal estimated cost (product of the tree sizes, the shape of the edit distance
            // cost). Tasks are submitted heaviest first, so one large pair does not keep a long run
            // of other work on a single core.
            let order = classes.indices.sorted { trees[classes[$0][0]].nodeCount > trees[classes[$1][0]].nodeCount }
            let tasks = Self.makeTasks(sizes: order.map { trees[classes[$0][0]].nodeCount }, workerCount: workerCount)
            let comparisonStart = ProcessInfo.processInfo.systemUptime
            var pairsFound = counts.identical
            report(.comparing, completed: 0, total: tasks.count, pairsFound: 0, since: comparisonStart)

            try await withThrowingTaskGroup(of: TaskResult.self) { group in
                var nextTask = 0
                func submitNext() {
                    guard nextTask < tasks.count else { return }
                    let task = tasks[nextTask]
                    nextTask += 1
                    let costs = costs
                    group.addTask {
                        Self.compare(task, order: order, classes: classes, elements: elements, trees: trees, threshold: threshold, costs: costs)
                    }
                }
                for _ in 0..<workerCount { submitNext() }

                var completedTasks = 0
                for try await result in group {
                    blocks.append(contentsOf: result.blocks)
                    counts.add(result.counts)
                    pairsFound += result.counts.similar
                    completedTasks += 1
                    report(.comparing, completed: completedTasks, total: tasks.count, pairsFound: pairsFound, since: comparisonStart)
                    submitNext()
                }
            }
        }

        let selection = Self.selectPairs(from: blocks, classes: classes, elements: elements, maxPairs: maxPairs, including: include)

        let totalTime = ProcessInfo.processInfo.systemUptime - startTime
        let statistics = ScanStatistics(
            elementCount: elements.count,
            totalPairs: elements.count * max(0, elements.count - 1) / 2,
            nestedPairs: counts.nested,
            pairsRuledOutByUpperBound: counts.ruledOutByUpperBound,
            pairsCompared: counts.compared,
            similarPairs: selection.similarPairCount,
            workerCount: workerCount,
            fingerprintTime: fingerprintTime,
            comparisonTime: totalTime - fingerprintTime,
            distinctTreeCount: classes.count,
            identicalPairs: counts.identical
        )
        return Result(
            pairs: selection.pairs.map { (elements[$0.index1], elements[$0.index2], $0.similarity) },
            statistics: statistics,
            matchingPairCount: selection.matchingPairCount
        )
    }

    // MARK: - Identical Trees

    /// Element indices grouped by identical trees, each class in input order, classes in order of
    /// their first element.
    static func identicalClasses(_ trees: [PreparedTree]) -> [[Int]] {
        var classes: [[Int]] = []
        var classIndex: [PreparedTree.IdentityKey: Int] = [:]
        for (index, tree) in trees.enumerated() {
            let key = tree.identityKey
            if let existing = classIndex[key] {
                classes[existing].append(index)
            } else {
                classIndex[key] = classes.count
                classes.append([index])
            }
        }
        return classes
    }

    /// Every pair between two classes (or within one) has the same score.
    struct Block: Sendable {
        let similarity: Double
        /// Index of the class whose first element comes first; equal to `class2` for the pairs
        /// within one class
        let class1: Int
        let class2: Int
    }

    /// The pairs of `blocks` that are not nested and that `include` accepts, most similar first,
    /// ties by position in `elements`; at most `maxPairs` of them, holding no more than twice that
    /// many in memory at once.
    static func selectPairs(
        from blocks: [Block],
        classes: [[Int]],
        elements: [CodeElement],
        maxPairs: Int?,
        including include: PairPredicate?
    ) -> (pairs: [IndexedPair], similarPairCount: Int, matchingPairCount: Int) {
        let blocks = blocks.sorted { $0.similarity > $1.similarity }
        let byPosition: (IndexedPair, IndexedPair) -> Bool = { ($0.index1, $0.index2) < ($1.index1, $1.index2) }
        var kept: [IndexedPair] = []
        var similar = 0
        var matching = 0
        var start = 0
        while start < blocks.count {
            // One score at a time: pairs with equal scores are ordered by position.
            var end = start
            while end < blocks.count && blocks[end].similarity == blocks[start].similarity { end += 1 }
            let remaining = maxPairs.map { max(0, $0 - kept.count) } ?? Int.max
            var level: [IndexedPair] = []
            func add(_ a: Int, _ b: Int, _ similarity: Double) {
                let (index1, index2) = a < b ? (a, b) : (b, a)
                guard !elements[index1].isNested(with: elements[index2]) else { return }
                similar += 1
                if let include, !include(elements[index1], elements[index2]) { return }
                matching += 1
                guard remaining > 0 else { return }
                level.append(IndexedPair(index1: index1, index2: index2, similarity: similarity))
                if remaining < Int.max / 2 && level.count >= 2 * remaining {
                    level.sort(by: byPosition)
                    level.removeLast(level.count - remaining)
                }
            }
            for block in blocks[start..<end] {
                let members1 = classes[block.class1]
                if block.class1 == block.class2 {
                    for a in 0..<members1.count {
                        for b in (a + 1)..<members1.count {
                            add(members1[a], members1[b], block.similarity)
                        }
                    }
                } else {
                    for a in members1 {
                        for b in classes[block.class2] {
                            add(a, b, block.similarity)
                        }
                    }
                }
            }
            level.sort(by: byPosition)
            if level.count > remaining {
                level.removeLast(level.count - remaining)
            }
            kept.append(contentsOf: level)
            start = end
        }
        return (kept, similar, matching)
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
    struct IndexedPair: Sendable {
        let index1: Int
        let index2: Int
        let similarity: Double
    }

    /// How many pairs each step skipped or compared
    private struct PairCounts: Sendable {
        var nested = 0
        var ruledOutByUpperBound = 0
        var compared = 0
        var identical = 0
        /// Pairs found similar by comparing (not counting `identical`), for progress reports
        var similar = 0

        mutating func add(_ other: PairCounts) {
            nested += other.nested
            ruledOutByUpperBound += other.ruledOutByUpperBound
            compared += other.compared
            identical += other.identical
            similar += other.similar
        }
    }

    private struct TaskResult: Sendable {
        let blocks: [Block]
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

    /// Compares class `order[task.row]` with the classes at `task.positions` in `order`, through
    /// the first element of each class. Counts are per pair of elements.
    private static func compare(
        _ task: PairTask,
        order: [Int],
        classes: [[Int]],
        elements: [CodeElement],
        trees: [PreparedTree],
        threshold: Double,
        costs: APTED.OperationCosts
    ) -> TaskResult {
        let calculator = SimilarityCalculator(configuration: .init(aptedCosts: costs))
        var blocks: [Block] = []
        var counts = PairCounts()
        let row = order[task.row]
        for position in task.positions {
            let other = order[position]
            let (class1, class2) = classes[row][0] < classes[other][0] ? (row, other) : (other, row)
            let members1 = classes[class1]
            let members2 = classes[class2]
            let first = members1[0]
            let second = members2[0]
            let pairCount = members1.count * members2.count

            // A declaration and one nested inside it share code; never report them as similar.
            // Without copies, this is checked first, since it is cheaper than the bound.
            if pairCount == 1 && elements[first].isNested(with: elements[second]) {
                counts.nested += 1
                continue
            }
            // Exact prefilter: the TSED upper bound from label histograms. Unlike heuristic
            // filters this never rejects a pair that would match.
            guard trees[first].tsedUpperBound(to: trees[second], costs: costs) >= threshold else {
                counts.ruledOutByUpperBound += pairCount
                continue
            }
            var comparedPairs = 1
            if pairCount > 1 {
                var nested = 0
                for a in members1 {
                    for b in members2 where elements[a].isNested(with: elements[b]) {
                        nested += 1
                    }
                }
                counts.nested += nested
                comparedPairs = pairCount - nested
                guard comparedPairs > 0 else { continue }
            }
            // TSED: tree edit distance normalized by the larger tree size (skipped when a cheaper
            // exact lower bound on the distance already rules the pair out)
            counts.compared += comparedPairs
            if let similarity = calculator.similarity(between: trees[first], and: trees[second], atLeast: threshold) {
                blocks.append(Block(similarity: similarity, class1: class1, class2: class2))
                counts.similar += comparedPairs
            }
        }
        return TaskResult(blocks: blocks, counts: counts)
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
