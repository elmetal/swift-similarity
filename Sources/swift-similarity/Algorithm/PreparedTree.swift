import Foundation

// MARK: - Label Interner

/// Assigns dense integer ids to node labels, so comparisons test `Int`s instead of `String`s.
///
/// Trees that are compared with each other must be prepared with the same interner.
public struct LabelInterner: Sendable {
    private var ids: [String: Int] = [:]

    public init() {}

    /// Number of distinct labels seen so far
    public var count: Int { ids.count }

    /// The id of `label`, assigning the next free id when it is new.
    public mutating func id(for label: String) -> Int {
        if let id = ids[label] { return id }
        let id = ids.count
        ids[label] = id
        return id
    }
}

// MARK: - Prepared Tree

/// Everything the tree edit distance and its lower bounds derive from a single tree, computed once.
///
/// A scan compares each element with many others; preparing every tree up front avoids redoing
/// this per pair. Use `APTED.editDistance(between:and:)`, `APTED.lowerBound(between:and:exceeding:)`
/// and `SimilarityCalculator.similarity(between:and:atLeast:)` with trees prepared by the same
/// `LabelInterner`.
public struct PreparedTree: Sendable {
    /// Number of nodes in the tree
    public let nodeCount: Int
    /// Label ids in preorder
    let preorder: [Int]
    /// Postorder index of the tree, children left to right
    let indexed: IndexedTree
    /// Postorder index of the mirror image (children right to left)
    let mirrored: IndexedTree
    /// Label histogram: distinct label ids in increasing order, with their number of nodes
    let histogram: [(label: Int, count: Int)]

    /// Label ids in postorder
    var postorder: [Int] { indexed.labels }

    /// - Parameters:
    ///   - root: The tree to prepare
    ///   - labels: Assigns label ids; share it between all trees that are compared with each other
    public init(_ root: TreeNode, labels: inout LabelInterner) {
        let flat = FlatTree(root)
        self.init(flat, labelIds: flat.labels.map { labels.id(for: $0) })
    }

    /// Prepares a flattened tree whose local label `k` has the id `labelIds[k]`.
    init(_ flat: FlatTree, labelIds: [Int]) {
        let n = flat.labelIndices.count
        nodeCount = n
        let preorder = flat.labelIndices.map { labelIds[$0] }
        self.preorder = preorder

        // A subtree is a contiguous block in preorder and in postorder; its postorder block ends
        // at the root, which comes after the root's descendants and before its later siblings:
        // post(p) = pre(p) + size(p) - 1 - depth(p) (0-based). The leftmost leaf starts the block.
        var postorder = [Int](repeating: 0, count: n)
        var leftmost = [Int](repeating: 0, count: n + 1)
        // Mirroring reverses every child list, so the mirror's postorder is the reverse of the
        // preorder, and its blocks are the preorder blocks reversed.
        var mirroredLeftmost = [Int](repeating: 0, count: n + 1)
        for p in 0..<n {
            let size = flat.sizes[p]
            let post = p + size - 1 - flat.depths[p]
            postorder[post] = preorder[p]
            leftmost[post + 1] = post + 1 - size + 1
            let mirroredPost = n - 1 - p
            mirroredLeftmost[mirroredPost + 1] = mirroredPost + 1 - size + 1
        }
        indexed = IndexedTree(labels: postorder, leftmost: leftmost)
        mirrored = IndexedTree(labels: Array(preorder.reversed()), leftmost: mirroredLeftmost)

        var histogram: [(label: Int, count: Int)] = []
        for label in preorder.sorted() {
            if let last = histogram.last, last.label == label {
                histogram[histogram.count - 1].count += 1
            } else {
                histogram.append((label, 1))
            }
        }
        self.histogram = histogram
    }
}

// MARK: - Flat Tree

/// A tree in preorder arrays, with labels numbered locally (first seen first).
///
/// Flattening walks the `TreeNode`s and hashes each label once; it needs no shared state, so a
/// scan flattens all trees in parallel and then maps only the few distinct labels of each tree
/// to scan-wide ids.
struct FlatTree: Sendable {
    /// Distinct labels; local label `k` is `labels[k]`
    let labels: [String]
    /// Local label of each node in preorder
    let labelIndices: [Int]
    /// Number of nodes in each node's subtree, in preorder
    let sizes: [Int]
    /// Depth of each node (root 0), in preorder
    let depths: [Int]

    init(_ root: TreeNode) {
        var labels: [String] = []
        var localIds: [String: Int] = [:]
        var labelIndices: [Int] = []
        var depths: [Int] = []
        var parents: [Int] = []
        // Iterative preorder, for deep ASTs.
        var stack: [(node: TreeNode, depth: Int, parent: Int)] = [(root, 0, -1)]
        while let (node, depth, parent) = stack.popLast() {
            let index = labelIndices.count
            if let id = localIds[node.label] {
                labelIndices.append(id)
            } else {
                localIds[node.label] = labels.count
                labelIndices.append(labels.count)
                labels.append(node.label)
            }
            depths.append(depth)
            parents.append(parent)
            for child in node.children.reversed() {
                stack.append((child, depth + 1, index))
            }
        }
        // Children come after their parent in preorder, so one backward pass sums subtree sizes.
        var sizes = [Int](repeating: 1, count: labelIndices.count)
        for p in stride(from: labelIndices.count - 1, to: 0, by: -1) {
            sizes[parents[p]] += sizes[p]
        }
        self.labels = labels
        self.labelIndices = labelIndices
        self.sizes = sizes
        self.depths = depths
    }
}

// MARK: - Label Histogram Bound

extension PreparedTree {
    /// Same as `ASTNodeFingerprint.treeEditDistanceLowerBound(to:costs:)`, from the interned
    /// histograms (a merge of two sorted arrays instead of dictionary lookups by label).
    public func treeEditDistanceLowerBound(to other: PreparedTree, costs: APTED.OperationCosts = APTED.OperationCosts()) -> Double {
        var excessSelf = 0
        var excessOther = 0
        histogram.withUnsafeBufferPointer { mine in
        other.histogram.withUnsafeBufferPointer { theirs in
            var i = 0
            var j = 0
            while i < mine.count && j < theirs.count {
                let a = mine[i]
                let b = theirs[j]
                if a.label == b.label {
                    if a.count > b.count { excessSelf += a.count - b.count } else { excessOther += b.count - a.count }
                    i += 1
                    j += 1
                } else if a.label < b.label {
                    excessSelf += a.count
                    i += 1
                } else {
                    excessOther += b.count
                    j += 1
                }
            }
            while i < mine.count { excessSelf += mine[i].count; i += 1 }
            while j < theirs.count { excessOther += theirs[j].count; j += 1 }
        }}
        return ASTNodeFingerprint.treeEditDistanceLowerBound(excessSelf: excessSelf, excessOther: excessOther, costs: costs)
    }

    /// Same as `ASTNodeFingerprint.tsedUpperBound(to:costs:)`, from the interned histograms.
    // similarity-ignore: the same bound for another representation; both call the shared formula
    public func tsedUpperBound(to other: PreparedTree, costs: APTED.OperationCosts = APTED.OperationCosts()) -> Double {
        ASTNodeFingerprint.tsedUpperBound(
            distanceLowerBound: treeEditDistanceLowerBound(to: other, costs: costs),
            maxNodes: max(nodeCount, other.nodeCount)
        )
    }
}

// MARK: - Indexed Tree

/// Postorder-indexed representation of a tree used by the Zhang–Shasha algorithm.
/// Node indices are 1-based; index 0 is unused.
struct IndexedTree: Sendable {
    /// Label ids in postorder (0-based array, node `i` is at `labels[i - 1]`).
    private(set) var labels: [Int] = []
    /// `leftmost[i]` is the postorder index of the leftmost leaf descendant of node `i`.
    private(set) var leftmost: [Int] = [0]
    /// Keyroots in increasing postorder.
    private(set) var keyroots: [Int] = []
    /// Sum of keyroot subtree sizes; Zhang–Shasha's work is proportional to the product of
    /// this value for both trees.
    private(set) var keyrootCost: Int = 0

    var count: Int { labels.count }

    /// - Parameters:
    ///   - labels: Label ids in postorder
    ///   - leftmost: `leftmost[i]` for 1-based postorder indices, with an unused `leftmost[0]`
    init(labels: [Int], leftmost: [Int]) {
        self.labels = labels
        self.leftmost = leftmost
        // Keyroots: for each distinct leftmost leaf, the highest node having it. Nodes sharing a
        // leftmost leaf lie on one path, and the highest of them comes last in postorder.
        var highest = [Int](repeating: 0, count: labels.count + 1)
        for i in 1...labels.count {
            highest[leftmost[i]] = i
        }
        keyroots = highest.filter { $0 > 0 }.sorted()
        keyrootCost = keyroots.reduce(0) { $0 + $1 - leftmost[$1] + 1 }
    }
}
