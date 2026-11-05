import Testing
import Foundation
@testable import swift_similarity

private func element(_ name: String, code: String) -> CodeElement {
    CodeElement(
        elementType: .function, name: name, signature: code, filePath: "/test.swift",
        startLine: 1, endLine: 5, codePreview: code, treeNode: SimpleTreeNode(label: name)
    )
}

private let parseHeader = element("parseHeader", code: "func parseHeader() { URLSession.shared }")
private let parseBody = element("parseBody", code: "func parseBody() { decoder.decode() }")
private let render = element("render", code: "func render() { URLSession.shared }")
private let layout = element("layout", code: "func layout() { view.layoutIfNeeded() }")

private let pairs: [SimilarityScanner.Pair] = [
    (parseHeader, parseBody, 0.95),
    (render, layout, 0.9),
    (layout, parseBody, 0.85),
    (render, parseHeader, 0.8),
]

private func names(_ pairs: [SimilarityScanner.Pair]) -> [String] {
    pairs.map { "\($0.first.name)/\($0.second.name)" }
}

@Test("An empty filter keeps every pair")
func testEmptyFilter() {
    #expect(PairFilter().isEmpty)
    #expect(PairFilter(nameContains: "", codeContains: "").isEmpty)
    #expect(names(PairFilter().apply(to: pairs)) == names(pairs))
}

@Test("A name filter keeps pairs where either declaration's name matches, ignoring case")
func testNameFilter() {
    let filter = PairFilter(nameContains: "PARSE")
    #expect(names(filter.apply(to: pairs)) == ["parseHeader/parseBody", "layout/parseBody", "render/parseHeader"])
}

@Test("A code filter is case-sensitive and combines with the name filter per declaration")
func testCodeFilter() {
    #expect(names(PairFilter(codeContains: "URLSession").apply(to: pairs)) == ["parseHeader/parseBody", "render/layout", "render/parseHeader"])
    #expect(PairFilter(codeContains: "urlsession").apply(to: pairs).isEmpty)
    // One declaration must match both: parseHeader does, render and parseBody match only one each.
    let both = PairFilter(nameContains: "parse", codeContains: "URLSession")
    #expect(names(both.apply(to: pairs)) == ["parseHeader/parseBody", "render/parseHeader"])
}

@Test("Declarations skipped by similarity-ignore are reported with their comment")
func testIgnoredDeclarations() throws {
    let source = """
        // similarity-ignore: generated
        func generated() { print(1) }

        /* similarity-ignore */
        struct Ignored {
            func kept() { print(1) }
        }

        func normal() { print(1) }
        """

    let functions = try extraction(of: source, configuration: .init(elementTypes: [.function], minLines: 0))
    #expect(functions.elements.map(\.name) == ["kept", "normal"])
    // Only declarations of the selected element types are listed.
    #expect(functions.ignored.map(\.name) == ["generated"])
    let generated = try #require(functions.ignored.first)
    #expect(generated.elementType == .function)
    #expect(generated.comment == "// similarity-ignore: generated")
    #expect(generated.startLine == 2 && generated.endLine == 2)

    let all = try extraction(of: source, configuration: .init(minLines: 0))
    #expect(all.ignored.map(\.name) == ["generated", "Ignored"])
    #expect(all.ignored.last?.comment == "/* similarity-ignore */")

    let notHonored = try extraction(of: source, configuration: .init(minLines: 0, respectIgnoreDirectives: false))
    #expect(notHonored.ignored.isEmpty)
    #expect(notHonored.elements.count == 4)
}
