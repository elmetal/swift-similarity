import Foundation
@testable import swift_similarity

// MARK: - Extraction From Source Text

/// Extracts `source` as if it were a Swift file: it is written to a uniquely named temporary file,
/// which is removed afterwards, so tests can run in parallel.
func extraction(
    of source: String,
    configuration: CodeElementExtractor.Configuration = .init()
) throws -> CodeElementExtractor.Extraction {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swift-similarity-test-\(UUID().uuidString).swift")
    try source.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    return try CodeElementExtractor(configuration: configuration).extract(fromPaths: [url.path])
}

/// The code elements of `source` (see `extraction(of:configuration:)`).
func extractElements(
    from source: String,
    configuration: CodeElementExtractor.Configuration = .init()
) throws -> [CodeElement] {
    try extraction(of: source, configuration: configuration).elements
}

// MARK: - Random Trees

/// A small seeded random number generator (SplitMix64), so randomized tests are reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

/// A random tree of exactly `size` nodes (at least 1) with labels drawn from `labels`.
func randomTree(size: Int, labels: [String], using rng: inout some RandomNumberGenerator) -> TreeNode {
    let label = labels.randomElement(using: &rng)!
    var remaining = size - 1
    var children: [TreeNode] = []
    while remaining > 0 {
        let childSize = Int.random(in: 1...remaining, using: &rng)
        children.append(randomTree(size: childSize, labels: labels, using: &rng))
        remaining -= childSize
    }
    return SimpleTreeNode(label: label, children: children)
}
