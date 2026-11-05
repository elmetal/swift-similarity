import Testing
import Foundation
@testable import swift_similarity

private let nestedSource = """
class Container {
    func method() {
        func helper() { print(1) }
        helper()
    }
}

struct Other {
    func method() {
        func helper() { print(1) }
        helper()
    }
}
func a() { print(1) }; func b() { print(1) }
"""

private func extractAll() throws -> [CodeElement] {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NestedPairs-\(UUID().uuidString).swift")
    try nestedSource.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    return try CodeElementExtractor().extractElements(from: url.path)
}

private func nestedPairKeys(_ elements: [CodeElement]) -> Set<String> {
    var keys: Set<String> = []
    for i in 0..<elements.count {
        for j in (i + 1)..<elements.count where elements[i].isNested(with: elements[j]) {
            keys.insert(pairKey(elements[i], elements[j]))
        }
    }
    return keys
}

private func pairKey(_ e1: CodeElement, _ e2: CodeElement) -> String {
    ["\(e1.name)@\(e1.startLine)", "\(e2.name)@\(e2.startLine)"].sorted().joined(separator: "|")
}

@Test("Nesting is detected by source ranges, not by name or line")
func testIsNested() throws {
    let elements = try extractAll()
    func element(_ name: String, line: Int) -> CodeElement {
        elements.first { $0.name == name && $0.startLine == line }!
    }
    
    // Container ⊃ method ⊃ helper (and Container ⊃ helper)
    #expect(element("Container", line: 1).isNested(with: element("method", line: 2)))
    #expect(element("method", line: 2).isNested(with: element("helper", line: 3)))
    #expect(element("helper", line: 3).isNested(with: element("Container", line: 1)))
    
    // Same names in a different declaration are not nested
    #expect(!element("method", line: 2).isNested(with: element("method", line: 9)))
    #expect(!element("Container", line: 1).isNested(with: element("Other", line: 8)))
    
    // Two functions on the same line are not nested
    #expect(!element("a", line: 14).isNested(with: element("b", line: 14)))
}

@Test("Scanner never reports a declaration together with one nested inside it")
func testScannerSkipsNestedPairs() async throws {
    let elements = try extractAll()
    let nested = nestedPairKeys(elements)
    #expect(nested.count == 6) // Container⊃{method,helper}, method⊃helper, same for Other
    
    let totalPairs = elements.count * (elements.count - 1) / 2
    
    // Threshold 0 reports every pair except the nested ones
    let result = try await SimilarityScanner().scan(elements, threshold: 0.0)
    let keys = Set(result.pairs.map { pairKey($0.first, $0.second) })
    #expect(keys.isDisjoint(with: nested))
    #expect(result.pairs.count == totalPairs - nested.count)
    #expect(result.statistics.nestedPairs == nested.count)
}
