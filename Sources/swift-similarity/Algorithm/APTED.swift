import Foundation

// MARK: - Tree Edit Distance

/// Computes the ordered, labeled tree edit distance between two trees.
///
/// The distance is the minimum total cost of node deletions, insertions and
/// renames (label substitutions) that transform the first tree into the second,
/// as used by TSED (arXiv:2404.08817).
///
/// This implementation uses the Zhang–Shasha dynamic programming algorithm.
/// It returns exactly the same distance as APTED (Pawlik & Augsten); APTED only
/// differs in choosing decomposition paths to reduce the running time.
/// Time: O(|T1|·|T2|·min(depth1, leaves1)·min(depth2, leaves2)), memory: O(|T1|·|T2|).
public class APTED {

    /// Operation costs for tree edit operations.
    public struct OperationCosts: Sendable, Equatable {
        /// Cost of inserting a node.
        public let insertion: Double
        /// Cost of deleting a node.
        public let deletion: Double
        /// Cost of substituting a node label.
        public let substitution: Double

        /// Creates operation costs with specified values.
        /// - Parameters:
        ///   - insertion: Cost of insertion (default: 1.0)
        ///   - deletion: Cost of deletion (default: 1.0)
        ///   - substitution: Cost of substitution (default: 1.0)
        public init(insertion: Double = 1.0, deletion: Double = 1.0, substitution: Double = 1.0) {
            self.insertion = insertion
            self.deletion = deletion
            self.substitution = substitution
        }
    }

    /// The operation costs used for calculations.
    public let costs: OperationCosts

    /// Creates a tree edit distance calculator with specified operation costs.
    /// - Parameter costs: The operation costs to use
    public init(costs: OperationCosts = OperationCosts()) {
        self.costs = costs
    }

    /// Computes the edit distance between two trees.
    /// - Parameters:
    ///   - tree1: The source tree
    ///   - tree2: The target tree
    /// - Returns: The minimum cost of transforming `tree1` into `tree2`
    public func editDistance(between tree1: TreeNode, and tree2: TreeNode) -> Double {
        var labels = LabelInterner()
        return editDistance(between: PreparedTree(tree1, labels: &labels), and: PreparedTree(tree2, labels: &labels))
    }

    /// Computes the edit distance between two trees prepared with the same `LabelInterner`.
    public func editDistance(between tree1: PreparedTree, and tree2: PreparedTree) -> Double {
        // Mirroring both trees (reversing every child list) does not change the distance, but
        // Zhang–Shasha's cost depends on the orientation: its work is the product of the sums of
        // keyroot subtree sizes. Run it on whichever orientation is cheaper.
        if tree1.mirrored.keyrootCost * tree2.mirrored.keyrootCost < tree1.indexed.keyrootCost * tree2.indexed.keyrootCost {
            return zhangShasha(tree1.mirrored, tree2.mirrored)
        }
        return zhangShasha(tree1.indexed, tree2.indexed)
    }
    
    /// A lower bound of `editDistance(between:and:)` computed in O(|T1|·|T2|) time.
    ///
    /// It is the larger of the string edit distances between the preorder and between the postorder
    /// label sequences, using the same costs. Deleting, inserting or renaming a tree node deletes,
    /// inserts or substitutes exactly one symbol of either sequence (a deleted node's children take
    /// its place in order), so every tree edit script maps to a string edit script of the same cost.
    /// The two orders catch different structural changes: moving a node between parent and sibling
    /// can leave one sequence unchanged but not both.
    ///
    /// - Parameter limit: The largest distance the caller can accept. When the bound exceeds a
    ///   non-negative `limit`, the result is some lower bound larger than `limit` (not necessarily
    ///   the largest one), which lets the computation stop early: the postorder bound is skipped
    ///   when the preorder bound already exceeds it, and each string edit distance only computes
    ///   the cells that a script within `limit` could pass through.
    public func lowerBound(between tree1: TreeNode, and tree2: TreeNode, exceeding limit: Double? = nil) -> Double {
        var labels = LabelInterner()
        return lowerBound(between: PreparedTree(tree1, labels: &labels), and: PreparedTree(tree2, labels: &labels), exceeding: limit)
    }

    /// `lowerBound(between:and:exceeding:)` for trees prepared with the same `LabelInterner`.
    public func lowerBound(between tree1: PreparedTree, and tree2: PreparedTree, exceeding limit: Double? = nil) -> Double {
        let preorderBound = stringEditDistance(tree1.preorder, tree2.preorder, limit: limit)
        if let limit, preorderBound > limit {
            return preorderBound
        }
        return max(preorderBound, stringEditDistance(tree1.postorder, tree2.postorder, limit: limit))
    }
    
    /// Edit distance between two label sequences with this calculator's costs.
    ///
    /// With a non-negative `limit`, distances above it are not computed exactly: the result is then
    /// some value in (limit, distance].
    private func stringEditDistance(_ sequence1: [Int], _ sequence2: [Int], limit: Double?) -> Double {
        let limit = limit.flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
        if let integral = integralCosts(maxDistanceSteps: sequence1.count + sequence2.count) {
            // Whole-number costs: exact Int32 arithmetic. Distances up to floor(limit) + 1 are
            // exact, so a distance that the caller's floating-point test may still accept (limit
            // itself is rounded) is never replaced by a smaller value; a larger one is reported as
            // floor(limit) + 2, a whole cost unit above `limit`.
            let maxDistance = Double(sequence1.count + sequence2.count) * Self.maxIntegerCost
            let cutoff = limit.map { Int32(min($0.rounded(.down) + 1, maxDistance)) }
            let distance = Self.stringEditDistance(sequence1, sequence2, costs: integral, cutoff: cutoff)
            return Double(distance ?? cutoff! + 1)
        }
        // Fractional costs: compute everything up to a slightly larger cutoff, for the same reason
        // and because rounding in sums of costs could put a path a hair below `limit`; a distance
        // above the cutoff is reported as the cutoff.
        let cutoff = limit.map { $0 + max(1, $0) * 1e-6 }
        let costs = (deletion: costs.deletion, insertion: costs.insertion, substitution: costs.substitution)
        return Self.stringEditDistance(sequence1, sequence2, costs: costs, cutoff: cutoff) ?? cutoff!
    }
    
    /// Two-row edit distance DP restricted to the band of cells reachable within `cutoff`.
    ///
    /// A cell (i, j) with i - j > cutoff / deletion needs more deletions than the cutoff allows
    /// (likewise for insertions); such cells count as infinite. Every cell on a path that costs at
    /// most `cutoff` lies in the band, so a distance up to `cutoff` is exact.
    /// - Returns: The distance, or nil if it exceeds `cutoff`
    private static func stringEditDistance<Cost: EditCost>(
        _ sequence1: [Int],
        _ sequence2: [Int],
        costs: (deletion: Cost, insertion: Cost, substitution: Cost),
        cutoff: Cost?
    ) -> Cost? {
        let (del, ins, sub) = costs
        let n = sequence1.count
        let m = sequence2.count
        let maxDeletions = cutoff.map { Cost.steps(of: del, within: $0) } ?? Int.max
        let maxInsertions = cutoff.map { Cost.steps(of: ins, within: $0) } ?? Int.max
        if n - m > maxDeletions || m - n > maxInsertions { return nil }
        
        // previous/current[j]: distance between the first i - 1 / i symbols of sequence1 and the
        // first j of sequence2. Cells just outside the band hold `infinity`.
        var previous = [Cost](repeating: .infinity, count: m + 1)
        var current = [Cost](repeating: .infinity, count: m + 1)
        for j in 0...min(m, maxInsertions) {
            previous[j] = Cost(exactly: j)! * ins
        }
        
        var result: Cost?
        sequence1.withUnsafeBufferPointer { s1 in
        sequence2.withUnsafeBufferPointer { s2 in
        previous.withUnsafeMutableBufferPointer { previousRow in
        current.withUnsafeMutableBufferPointer { currentRow in
            var prev = previousRow
            var cur = currentRow
            for i in 1...n {
                let low = i > maxDeletions ? i - maxDeletions : 1
                let high = min(m, maxInsertions >= m ? m : i + maxInsertions)
                // Left edge: column 0 while it is in the band, otherwise the cell just outside.
                var left: Cost = .infinity
                if i <= maxDeletions {
                    left = Cost(exactly: i)! * del
                    cur[0] = left
                } else {
                    cur[low - 1] = .infinity
                }
                var rowMinimum = left
                if low <= high {
                    let symbol = s1[i - 1]
                    for j in low...high {
                        // Only the insertion depends on the cell just computed, so take the
                        // minimum of the other two first (see zhangShasha).
                        let rename = prev[j - 1] + (symbol == s2[j - 1] ? 0 : sub)
                        left = min(min(prev[j] + del, rename), left + ins)
                        cur[j] = left
                        rowMinimum = min(rowMinimum, left)
                    }
                    // The next row reads one cell further right, outside this row's band.
                    if high < m { cur[high + 1] = .infinity }
                }
                // Costs are non-negative, so no later row has a smaller minimum.
                if let cutoff, rowMinimum > cutoff { return }
                swap(&prev, &cur)
            }
            let distance = prev[m]
            if let cutoff, distance > cutoff { return }
            result = distance
        }}}}
        return result
    }
    
    /// Largest whole-number cost handled with Int32 arithmetic
    private static let maxIntegerCost = 1024.0
    
    /// The costs as Int32 when they are whole numbers small enough that no distance between
    /// trees or sequences of `maxDistanceSteps` nodes in total can overflow (with room for
    /// `Int32.infinity`). Doubles hold these integers exactly, so results are the same.
    private func integralCosts(maxDistanceSteps: Int) -> (deletion: Int32, insertion: Int32, substitution: Int32)? {
        let values = [costs.deletion, costs.insertion, costs.substitution]
        guard values.allSatisfy({ $0 >= 0 && $0 <= Self.maxIntegerCost && $0 == $0.rounded() }),
              Double(maxDistanceSteps) * Self.maxIntegerCost < Double(Int32.max / 8) else { return nil }
        return (Int32(costs.deletion), Int32(costs.insertion), Int32(costs.substitution))
    }
    
    // MARK: - Zhang–Shasha
    
    private func zhangShasha(_ t1: IndexedTree, _ t2: IndexedTree) -> Double {
        // With whole-number costs (the default) every distance is a small integer, so the tables
        // can hold Int32: half the memory, and cheaper additions and comparisons.
        if let integral = integralCosts(maxDistanceSteps: t1.count + t2.count) {
            return Double(Self.zhangShasha(t1, t2, costs: integral))
        }
        return Self.zhangShasha(t1, t2, costs: (costs.deletion, costs.insertion, costs.substitution))
    }
    
    private static func zhangShasha<Cost: EditCost>(
        _ t1: IndexedTree,
        _ t2: IndexedTree,
        costs: (deletion: Cost, insertion: Cost, substitution: Cost)
    ) -> Cost {
        let (del, ins, sub) = costs
        let n = t1.count
        let m = t2.count
        let width = m + 1
        
        // Label ids come from one LabelInterner, so the inner loop compares Ints, not Strings.
        let labels1 = t1.labels
        let labels2 = t2.labels
        
        // treeDist[i * width + j]: distance between subtree rooted at i (in t1) and j (in t2), 1-based postorder.
        var treeDist = [Cost](repeating: 0, count: (n + 1) * width)
        // forestDist is reused for every keyroot pair; it is indexed relative to the leftmost leaves.
        var forestDist = [Cost](repeating: 0, count: (n + 1) * width)
        
        // Unsafe buffers avoid bounds checks in the O(n²·depth²) inner loop; all indices stay
        // within the (n + 1) x (m + 1) tables by construction.
        labels1.withUnsafeBufferPointer { l1 in
        labels2.withUnsafeBufferPointer { l2 in
        t1.leftmost.withUnsafeBufferPointer { lm1 in
        t2.leftmost.withUnsafeBufferPointer { lm2 in
        treeDist.withUnsafeMutableBufferPointer { td in
        forestDist.withUnsafeMutableBufferPointer { fd in
            for i in t1.keyroots {
                for j in t2.keyroots {
                    let li = lm1[i]
                    let lj = lm2[j]
                    let rows = i - li + 2
                    let cols = j - lj + 2
                    
                    // fd[x * width + y] with x in 0..<rows, y in 0..<cols
                    fd[0] = 0
                    for x in 1..<rows {
                        fd[x * width] = fd[(x - 1) * width] + del
                    }
                    for y in 1..<cols {
                        fd[y] = fd[y - 1] + ins
                    }
                    
                    for x in 1..<rows {
                        let i1 = li + x - 1
                        let li1 = lm1[i1]
                        let row = x * width
                        let previousRow = row - width
                        let label1 = l1[i1 - 1]
                        let isTree1 = li1 == li
                        let prefixRow = (li1 - li) * width
                        let treeRow = i1 * width
                        for y in 1..<cols {
                            let j1 = lj + y - 1
                            let lj1 = lm2[j1]
                            
                            // Only the insertion depends on the cell just computed; take the
                            // minimum of the other two first so the loop-carried chain is one
                            // addition and one comparison.
                            let deleteCost = fd[previousRow + y] + del
                            let other: Cost
                            if isTree1 && lj1 == lj {
                                // Both prefixes are whole trees: rename the roots.
                                let renameCost = label1 == l2[j1 - 1] ? 0 : sub
                                other = min(deleteCost, fd[previousRow + y - 1] + renameCost)
                            } else {
                                // Match previously computed subtrees.
                                other = min(deleteCost, fd[prefixRow + lj1 - lj] + td[treeRow + j1])
                            }
                            let value = min(other, fd[row + y - 1] + ins)
                            if isTree1 && lj1 == lj {
                                td[treeRow + j1] = value
                            }
                            fd[row + y] = value
                        }
                    }
                }
            }
        }}}}}}
        
        return treeDist[n * width + m]
    }
}

// MARK: - Cost Types

/// Number types the dynamic programs run on: Int32 for whole-number costs, Double otherwise.
private protocol EditCost: Numeric, Comparable {
    /// A value larger than any distance, which stays larger after adding a few costs
    static var infinity: Self { get }
    /// An upper bound on the number of operations of `cost` that fit within `cutoff`; an edit
    /// script with more of them costs more than `cutoff`. `cost` and `cutoff` are non-negative.
    static func steps(of cost: Self, within cutoff: Self) -> Int
}

extension Int32: EditCost {
    static var infinity: Int32 { Int32.max / 4 }
    static func steps(of cost: Int32, within cutoff: Int32) -> Int {
        cost > 0 ? Int(cutoff / cost) : Int.max
    }
}

extension Double: EditCost {
    static func steps(of cost: Double, within cutoff: Double) -> Int {
        // One extra step absorbs rounding in sums of fractional costs.
        cost > 0 ? Int(min(cutoff / cost, Double(Int32.max))) + 1 : Int.max
    }
}
