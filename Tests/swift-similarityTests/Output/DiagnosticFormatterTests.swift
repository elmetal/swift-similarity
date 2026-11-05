import Testing
@testable import swift_similarity

private func element(_ name: String, file: String, line: Int, type: CodeElementType = .function) -> CodeElement {
    CodeElement(
        elementType: type, name: name, signature: name, filePath: file,
        startLine: line, endLine: line + 4, codePreview: name,
        treeNode: SimpleTreeNode(label: name), byteRange: line * 100..<(line * 100 + 10)
    )
}

private let root = "/repo"
private let a = element("load", file: "/repo/Sources/A.swift", line: 10)
private let b = element("reload", file: "/repo/Sources/A.swift", line: 30)
private let c = element("fetch", file: "/repo/Sources/B.swift", line: 5)

@Test("Xcode style: one warning per declaration, most similar first, absolute locations")
func testXcodeStyle() {
    let output = DiagnosticFormatter.format([(a, b, 0.9), (a, c, 0.95)], style: .xcode, messagePathsRelativeTo: root)
    #expect(output.split(separator: "\n") == [
        "/repo/Sources/A.swift:10:1: warning: function load is similar to function fetch (Sources/B.swift:5, 95.0%), function reload (line 30, 90.0%) [swift-similarity]",
        "/repo/Sources/A.swift:30:1: warning: function reload is similar to function load (line 10, 90.0%) [swift-similarity]",
        "/repo/Sources/B.swift:5:1: warning: function fetch is similar to function load (Sources/A.swift:10, 95.0%) [swift-similarity]",
    ])
}

@Test("GitHub style: relative paths, line range and escaped values")
func testGitHubStyle() {
    let output = DiagnosticFormatter.format([(a, c, 0.95)], style: .github, relativeTo: root, messagePathsRelativeTo: root)
    #expect(output.split(separator: "\n").first ==
        "::warning file=Sources/A.swift,line=10,endLine=14,title=Similar code (swift-similarity)::function load is similar to function fetch (Sources/B.swift:5, 95.0%25) [swift-similarity]")
    #expect(DiagnosticFormatter.escapeProperty("a,b:c%\n") == "a%2Cb%3Ac%25%0A")
    #expect(DiagnosticFormatter.format([], style: .github).isEmpty)
}

@Test("Long lists of similar declarations are cut with a count")
func testManyMatches() {
    let others = (0..<8).map { element("copy\($0)", file: "/repo/C.swift", line: 100 + $0 * 10) }
    let pairs = others.map { (a, $0, 0.9) }
    let first = DiagnosticFormatter.format(pairs, style: .xcode).split(separator: "\n").first { $0.contains("function load is") }
    #expect(first?.hasSuffix("and 3 more [swift-similarity]") == true)
    #expect(first?.components(separatedBy: "function copy").count == DiagnosticFormatter.maximumNamedMatches + 1)
}
