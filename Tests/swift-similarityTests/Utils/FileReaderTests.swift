import Testing
import Foundation
@testable import swift_similarity

@Test("findSwiftFiles throws for a path that is not a directory")
func testFindSwiftFilesRejectsMissingDirectory() throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-similarity-missing-\(UUID().uuidString)").path
    #expect(throws: (any Error).self) {
        try FileReader.findSwiftFiles(in: missing)
    }
    
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-similarity-file-\(UUID().uuidString).swift")
    try "let x = 1".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(throws: (any Error).self) {
        try FileReader.findSwiftFiles(in: file.path)
    }
}

@Test("findSwiftFiles returns only Swift files, sorted by path")
func testFindSwiftFilesIsSorted() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-similarity-dir-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["c.swift", "a.swift", "sub/b.swift", "notes.txt"] {
        try "".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    
    let files = try FileReader.findSwiftFiles(in: root.path)
    #expect(files.count == 3)
    #expect(files == files.sorted())
    #expect(files.allSatisfy { $0.hasSuffix(".swift") })
}
