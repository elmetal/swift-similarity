import Testing
@testable import swift_similarity

private func element(_ name: String, lines: ClosedRange<Int>) -> CodeElement {
    CodeElement(
        elementType: .function,
        name: name,
        signature: name,
        filePath: "/test/\(name).swift",
        startLine: lines.lowerBound,
        endLine: lines.upperBound,
        codePreview: "",
        treeNode: SimpleTreeNode(label: name)
    )
}

private func pair(_ name: String, _ lines1: ClosedRange<Int>, _ lines2: ClosedRange<Int>, _ similarity: Double) -> (CodeElement, CodeElement, Double) {
    (element("\(name)1", lines: lines1), element("\(name)2", lines: lines2), similarity)
}

private func names(_ pairs: [(CodeElement, CodeElement, Double)]) -> [String] {
    pairs.map { String($0.0.name.dropLast()) }
}

@Test("Line span counts both ends and is at least 1")
func lineSpan() {
    #expect(SimilarityRanking.lineSpan(of: element("a", lines: 3...12)) == 10)
    #expect(SimilarityRanking.lineSpan(of: element("a", lines: 5...5)) == 1)
}

@Test("Priority uses the smaller declaration's lines")
func priorityUsesSmallerSpan() {
    let p = pair("p", 1...10, 20...59, 0.85)
    #expect(SimilarityRanking.lines(of: p) == 10)
    #expect(abs(SimilarityRanking.priority(of: p) - 8.5) < 1e-9)
}

@Test("Similarity order sorts by score and keeps input order for ties")
func similarityOrder() {
    let pairs = [
        pair("a", 1...5, 1...5, 0.8),
        pair("b", 1...50, 1...50, 0.9),
        pair("c", 1...30, 1...30, 0.8),
        pair("d", 1...2, 1...2, 1.0),
    ]
    #expect(names(SimilarityRanking.sorted(pairs, by: .similarity)) == ["d", "b", "a", "c"])
}

@Test("Priority order puts large duplicates first")
func priorityOrder() {
    let pairs = [
        pair("small", 1...2, 1...2, 1.0),     // 2.0
        pair("large", 1...50, 1...60, 0.8),   // 40.0
        pair("medium", 1...10, 1...10, 0.9),  // 9.0
    ]
    #expect(names(SimilarityRanking.sorted(pairs, by: .priority)) == ["large", "medium", "small"])
}

@Test("Priority ties fall back to similarity, then input order")
func priorityTies() {
    let pairs = [
        pair("a", 1...10, 1...10, 0.8),  // 8.0
        pair("b", 1...8, 1...8, 1.0),    // 8.0, higher similarity
        pair("c", 1...10, 1...10, 0.8),  // 8.0, same as a
    ]
    #expect(names(SimilarityRanking.sorted(pairs, by: .priority)) == ["b", "a", "c"])
}

@Test("Sort order parses from its raw value")
func sortOrderRawValues() {
    #expect(SimilarityRanking.SortOrder(rawValue: "priority") == .priority)
    #expect(SimilarityRanking.SortOrder(rawValue: "similarity") == .similarity)
    #expect(SimilarityRanking.SortOrder(rawValue: "lines") == nil)
}
