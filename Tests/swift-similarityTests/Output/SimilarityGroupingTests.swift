import Testing
@testable import swift_similarity

private func element(_ name: String, line: Int, lines: Int = 10) -> CodeElement {
    CodeElement(
        elementType: .function, name: name, signature: name, filePath: "/test.swift",
        startLine: line, endLine: line + lines - 1, codePreview: name,
        treeNode: SimpleTreeNode(label: name), byteRange: line * 1000..<(line * 1000 + 10)
    )
}

private let a = element("a", line: 1)
private let b = element("b", line: 20)
private let c = element("c", line: 40)
private let d = element("d", line: 60)
private let e = element("e", line: 80, lines: 30)
private let f = element("f", line: 120, lines: 30)

private func names(_ group: SimilarityGrouping.Group) -> [String] {
    group.members.map(\.name)
}

private func names(_ pairs: [SimilarityGrouping.Pair]) -> [String] {
    pairs.map { "\($0.0.name)/\($0.1.name)" }
}

@Test("Copies of each other form one group, with every pair kept inside it")
func testCliqueBecomesOneGroup() {
    let pairs: [SimilarityGrouping.Pair] = [(a, b, 1.0), (a, c, 0.9), (b, c, 0.95), (a, d, 0.85), (b, d, 0.85), (c, d, 0.8)]
    let (groups, between) = SimilarityGrouping.group(pairs)
    #expect(groups.count == 1)
    #expect(names(groups[0]) == ["a", "b", "c", "d"])
    #expect(groups[0].pairs.count == 6)
    #expect(groups[0].minimumSimilarity == 0.8)
    #expect(groups[0].maximumSimilarity == 1.0)
    // (4 − 1) copies × 10 lines × 0.8
    #expect(groups[0].priority == 24)
    #expect(between.isEmpty)
}

@Test("A chain is not merged: declarations that are not similar stay in different groups")
func testChainIsSplit() {
    // a~b and b~c, but not a~c: complete linkage keeps the most similar pair together.
    let pairs: [SimilarityGrouping.Pair] = [(a, b, 0.85), (b, c, 0.95)]
    let (groups, between) = SimilarityGrouping.group(pairs)
    #expect(groups.map(names) == [["b", "c"]])
    #expect(names(between) == ["a/b"])
}

@Test("Groups are ordered by similarity or priority, and two-member groups match their pair")
func testGroupOrder() {
    let pairs: [SimilarityGrouping.Pair] = [(a, b, 0.9), (e, f, 0.85), (c, d, 0.95)]
    let bySimilarity = SimilarityGrouping.group(pairs, by: .similarity).groups
    #expect(bySimilarity.map(names) == [["c", "d"], ["a", "b"], ["e", "f"]])
    let byPriority = SimilarityGrouping.group(pairs, by: .priority).groups
    #expect(byPriority.map(names) == [["e", "f"], ["c", "d"], ["a", "b"]])
    for group in byPriority {
        let pair = group.pairs[0]
        #expect(group.priority == SimilarityRanking.priority(of: pair))
    }
}

@Test("Every pair ends up either in a group or between groups")
func testNoPairIsLost() {
    let pairs: [SimilarityGrouping.Pair] = [
        (a, b, 0.9), (b, c, 0.9), (c, d, 0.9), (a, c, 0.85), (d, e, 0.82), (e, f, 0.81), (b, f, 0.8),
    ]
    let (groups, between) = SimilarityGrouping.group(pairs)
    #expect(groups.reduce(0) { $0 + $1.pairs.count } + between.count == pairs.count)
    // Each declaration is in at most one group, and every two members of a group are a pair.
    let allMembers = groups.flatMap(names)
    #expect(Set(allMembers).count == allMembers.count)
    for group in groups {
        let n = group.members.count
        #expect(group.pairs.count == n * (n - 1) / 2)
    }
    #expect(SimilarityGrouping.group([]).groups.isEmpty)
}
