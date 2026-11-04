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
        // Mirroring both trees (reversing every child list) does not change the distance, but
        // Zhang–Shasha's cost depends on the orientation: its work is the product of the sums of
        // keyroot subtree sizes. Run it on whichever orientation is cheaper.
        let left1 = IndexedTree(tree1, mirrored: false)
        let left2 = IndexedTree(tree2, mirrored: false)
        let right1 = IndexedTree(tree1, mirrored: true)
        let right2 = IndexedTree(tree2, mirrored: true)
        if right1.keyrootCost * right2.keyrootCost < left1.keyrootCost * left2.keyrootCost {
            return zhangShasha(right1, right2)
        }
        return zhangShasha(left1, left2)
    }
    
    /// A lower bound of `editDistance(between:and:)` computed in O(|T1|·|T2|) time.
    ///
    /// It is the string edit distance between the preorder label sequences, using the same costs.
    /// Deleting, inserting or renaming a tree node deletes, inserts or substitutes exactly one
    /// symbol of the preorder sequence (a deleted node's children take its place in order), so
    /// every tree edit script maps to a string edit script of the same cost.
    public func lowerBound(between tree1: TreeNode, and tree2: TreeNode) -> Double {
        var labelIds: [String: Int] = [:]
        let sequence1 = preorderLabelIds(tree1, &labelIds)
        let sequence2 = preorderLabelIds(tree2, &labelIds)
        let del = costs.deletion
        let ins = costs.insertion
        let sub = costs.substitution
        
        var previous = (0...sequence2.count).map { Double($0) * ins }
        var current = [Double](repeating: 0, count: sequence2.count + 1)
        for i in 1...sequence1.count {
            current[0] = Double(i) * del
            let symbol = sequence1[i - 1]
            for j in 1...sequence2.count {
                let rename = previous[j - 1] + (symbol == sequence2[j - 1] ? 0 : sub)
                current[j] = min(previous[j] + del, current[j - 1] + ins, rename)
            }
            swap(&previous, &current)
        }
        return previous[sequence2.count]
    }
    
    private func preorderLabelIds(_ root: TreeNode, _ labelIds: inout [String: Int]) -> [Int] {
        var result: [Int] = []
        var stack: [TreeNode] = [root]
        while let node = stack.popLast() {
            if let id = labelIds[node.label] {
                result.append(id)
            } else {
                let id = labelIds.count
                labelIds[node.label] = id
                result.append(id)
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return result
    }
    
    // MARK: - Zhang–Shasha
    
    private func zhangShasha(_ t1: IndexedTree, _ t2: IndexedTree) -> Double {
        let n = t1.count
        let m = t2.count
        let width = m + 1
        
        // Integer label ids so the inner loop compares Ints, not Strings.
        var labelIds: [String: Int] = [:]
        func ids(_ labels: [String]) -> [Int] {
            labels.map { label in
                if let id = labelIds[label] { return id }
                let id = labelIds.count
                labelIds[label] = id
                return id
            }
        }
        let labels1 = ids(t1.labels)
        let labels2 = ids(t2.labels)
        
        let del = costs.deletion
        let ins = costs.insertion
        let sub = costs.substitution
        
        // treeDist[i * width + j]: distance between subtree rooted at i (in t1) and j (in t2), 1-based postorder.
        var treeDist = [Double](repeating: 0, count: (n + 1) * width)
        // forestDist is reused for every keyroot pair; it is indexed relative to the leftmost leaves.
        var forestDist = [Double](repeating: 0, count: (n + 1) * width)
        
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
                            
                            let deleteCost = fd[previousRow + y] + del
                            let insertCost = fd[row + y - 1] + ins
                            
                            let value: Double
                            if isTree1 && lj1 == lj {
                                // Both prefixes are whole trees: rename the roots.
                                let renameCost = label1 == l2[j1 - 1] ? 0 : sub
                                value = min(deleteCost, insertCost, fd[previousRow + y - 1] + renameCost)
                                td[treeRow + j1] = value
                            } else {
                                // Match previously computed subtrees.
                                value = min(deleteCost, insertCost, fd[prefixRow + lj1 - lj] + td[treeRow + j1])
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
    /// Sum of keyroot subtree sizes; Zhang–Shasha's work is proportional to the product of
    /// this value for both trees.
    var keyrootCost: Int = 0
    
    var count: Int { labels.count }
    
    /// - Parameters:
    ///   - root: The tree to index
    ///   - mirrored: Visit children right-to-left, indexing the mirror image of the tree
    init(_ root: TreeNode, mirrored: Bool) {
        // Iterative postorder to avoid stack overflow on deep ASTs.
        var stack: [(node: TreeNode, childIndex: Int, leftmost: Int)] = [(root, 0, 0)]
        while !stack.isEmpty {
            let top = stack.count - 1
            let node = stack[top].node
            let childIndex = stack[top].childIndex
            let childCount = node.children.count
            if childIndex < childCount {
                stack[top].childIndex += 1
                let child = node.children[mirrored ? childCount - 1 - childIndex : childIndex]
                stack.append((child, 0, 0))
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
        keyrootCost = keyroots.reduce(0) { $0 + $1 - leftmost[$1] + 1 }
    }
}
