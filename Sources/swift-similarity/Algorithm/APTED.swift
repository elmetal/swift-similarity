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
        let t1 = IndexedTree(tree1)
        let t2 = IndexedTree(tree2)
        return zhangShasha(t1, t2)
    }

    // MARK: - Zhang–Shasha

    private func zhangShasha(_ t1: IndexedTree, _ t2: IndexedTree) -> Double {
        let n = t1.count
        let m = t2.count
        let width = m + 1

        // Integer label ids so the inner loop compares Ints, not Strings.
        var labelIds: [String: Int] = [:]
        let labels1 = t1.labels.map { label -> Int in
            if let id = labelIds[label] { return id }
            let id = labelIds.count
            labelIds[label] = id
            return id
        }
        let labels2 = t2.labels.map { label -> Int in
            if let id = labelIds[label] { return id }
            let id = labelIds.count
            labelIds[label] = id
            return id
        }

        let del = costs.deletion
        let ins = costs.insertion
        let sub = costs.substitution

        // treeDist[i * width + j]: distance between subtree rooted at i (in t1) and j (in t2), 1-based postorder.
        var treeDist = [Double](repeating: 0, count: (n + 1) * width)
        // forestDist is reused for every keyroot pair; it is indexed relative to the leftmost leaves.
        var forestDist = [Double](repeating: 0, count: (n + 1) * width)

        for i in t1.keyroots {
            for j in t2.keyroots {
                let li = t1.leftmost[i]
                let lj = t2.leftmost[j]
                let rows = i - li + 2
                let cols = j - lj + 2

                // forestDist[x][y] with x in 0..<rows, y in 0..<cols, row stride = width
                forestDist[0] = 0
                for x in 1..<rows {
                    forestDist[x * width] = forestDist[(x - 1) * width] + del
                }
                for y in 1..<cols {
                    forestDist[y] = forestDist[y - 1] + ins
                }

                for x in 1..<rows {
                    let i1 = li + x - 1
                    let li1 = t1.leftmost[i1]
                    for y in 1..<cols {
                        let j1 = lj + y - 1
                        let lj1 = t2.leftmost[j1]

                        let deleteCost = forestDist[(x - 1) * width + y] + del
                        let insertCost = forestDist[x * width + y - 1] + ins

                        let value: Double
                        if li1 == li && lj1 == lj {
                            // Both prefixes are whole trees: rename the roots.
                            let renameCost = labels1[i1 - 1] == labels2[j1 - 1] ? 0 : sub
                            value = min(deleteCost, insertCost, forestDist[(x - 1) * width + y - 1] + renameCost)
                            treeDist[i1 * width + j1] = value
                        } else {
                            // Match previously computed subtrees.
                            let px = li1 - li
                            let py = lj1 - lj
                            value = min(deleteCost, insertCost, forestDist[px * width + py] + treeDist[i1 * width + j1])
                        }
                        forestDist[x * width + y] = value
                    }
                }
            }
        }

        return treeDist[n * width + m]
    }
}

// MARK: - Indexed Tree

/// Postorder-indexed representation of a tree used by the Zhang–Shasha algorithm.
/// Node indices are 1-based; index 0 is unused.
private struct IndexedTree {
    /// Labels in postorder (0-based array, node `i` is at `labels[i - 1]`).
    var labels: [String] = []
    /// `leftmost[i]` is the postorder index of the leftmost leaf descendant of node `i`.
    var leftmost: [Int] = [0]
    /// Keyroots in increasing postorder.
    var keyroots: [Int] = []

    var count: Int { labels.count }

    init(_ root: TreeNode) {
        // Iterative postorder to avoid stack overflow on deep ASTs.
        var stack: [(node: TreeNode, childIndex: Int, leftmost: Int)] = [(root, 0, 0)]
        while !stack.isEmpty {
            let top = stack.count - 1
            let node = stack[top].node
            let childIndex = stack[top].childIndex
            if childIndex < node.children.count {
                stack[top].childIndex += 1
                stack.append((node.children[childIndex], 0, 0))
                continue
            }
            let frame = stack.removeLast()
            labels.append(node.label)
            let index = labels.count
            // A leaf is its own leftmost leaf; otherwise inherit from the first child.
            let lml = node.children.isEmpty ? index : frame.leftmost
            leftmost.append(lml)
            // If this node is its parent's first child, record it for the parent.
            if let parent = stack.indices.last, stack[parent].childIndex == 1 {
                stack[parent].leftmost = lml
            }
        }

        // Keyroots: for each distinct leftmost leaf, the highest node having it.
        var highest: [Int: Int] = [:]
        for i in 1...count {
            highest[leftmost[i]] = i
        }
        keyroots = highest.values.sorted()
    }
}
