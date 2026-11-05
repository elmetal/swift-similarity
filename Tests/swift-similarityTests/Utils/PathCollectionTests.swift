import Testing
import Foundation
@testable import swift_similarity

/// Creates a temporary directory with empty files at the given relative paths.
private func makeTree(_ files: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-similarity-paths-\(UUID().uuidString)")
    for file in files {
        let url = root.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: url, atomically: true, encoding: .utf8)
    }
    return root
}

/// The paths of `files` relative to `root`.
private func relative(_ files: [String], to root: URL) -> [String] {
    let prefix = root.resolvingSymlinksInPath().path + "/"
    return files.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.replacingOccurrences(of: prefix, with: "") }
}

// MARK: - Exclude Patterns

@Test("A pattern without a slash matches any path component")
func testExcludePatternMatchesComponent() {
    let pattern = ExcludePattern("Tests")
    #expect(pattern.matches(path: "Tests"))
    #expect(pattern.matches(path: "Sub/Tests"))
    #expect(!pattern.matches(path: "Sub/Tests/A.swift")) // the directory itself is pruned instead
    #expect(!pattern.matches(path: "MyTests"))

    #expect(ExcludePattern("*.generated.swift").matches(path: "a/b/Model.generated.swift"))
    #expect(!ExcludePattern("*.generated.swift").matches(path: "a/b/Model.swift"))
}

@Test("** matches any number of components")
func testExcludePatternDoubleStar() {
    let pattern = ExcludePattern("**/Generated/**")
    #expect(pattern.matches(path: "Generated"))
    #expect(pattern.matches(path: "Sources/App/Generated"))
    #expect(pattern.matches(path: "Sources/App/Generated/Deep/A.swift"))
    #expect(!pattern.matches(path: "Sources/App/NotGenerated/A.swift"))

    #expect(ExcludePattern("Sources/**/*.swift").matches(path: "Sources/A.swift"))
    #expect(ExcludePattern("Sources/**/*.swift").matches(path: "Sources/x/y/A.swift"))
    #expect(ExcludePattern("./Generated/").matches(path: "Generated"))
    #expect(!ExcludePattern("").matches(path: "A.swift"))
}

// MARK: - Path Collection

@Test("findSwiftFiles(in: paths) accepts directories and files, deduplicated and sorted")
func testFindSwiftFilesFromSeveralPaths() throws {
    let root = try makeTree(["b/B.swift", "b/C.swift", "a/A.swift", "z.swift", "notes.txt"])
    defer { try? FileManager.default.removeItem(at: root) }

    let files = try FileReader.findSwiftFiles(in: [
        root.appendingPathComponent("b").path,
        root.appendingPathComponent("z.swift").path,
        root.appendingPathComponent("a").path,
        // Overlapping paths must not produce duplicates.
        root.appendingPathComponent("b/B.swift").path,
        root.path,
    ])
    #expect(relative(files, to: root) == ["a/A.swift", "b/B.swift", "b/C.swift", "z.swift"])
}

@Test("findSwiftFiles(in: paths) rejects missing paths and non-Swift files")
func testFindSwiftFilesRejectsInvalidPaths() throws {
    let root = try makeTree(["A.swift", "notes.txt"])
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: (any Error).self) {
        try FileReader.findSwiftFiles(in: [root.appendingPathComponent("missing").path])
    }
    #expect(throws: (any Error).self) {
        try FileReader.findSwiftFiles(in: [root.appendingPathComponent("notes.txt").path])
    }
    #expect(throws: Never.self) {
        try FileReader.findSwiftFiles(in: [root.appendingPathComponent("A.swift").path])
    }
}

@Test("Exclude patterns skip matching files and directories")
func testFindSwiftFilesExcludes() throws {
    let root = try makeTree([
        "Sources/App/A.swift",
        "Sources/App/Model.generated.swift",
        "Sources/App/Generated/G.swift",
        "Tests/AppTests/T.swift",
        ".build/debug/Hidden.swift",
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    let all = try FileReader.findSwiftFiles(in: [root.path])
    #expect(relative(all, to: root) == [
        "Sources/App/A.swift",
        "Sources/App/Generated/G.swift",
        "Sources/App/Model.generated.swift",
        "Tests/AppTests/T.swift",
    ])

    let patterns = ["Tests", "**/Generated/**", "*.generated.swift"].map(ExcludePattern.init)
    let filtered = try FileReader.findSwiftFiles(in: [root.path], excluding: patterns)
    #expect(relative(filtered, to: root) == ["Sources/App/A.swift"])
}

@Test("Exclude patterns are matched relative to each scanned directory")
func testExcludeIsRelativeToScannedDirectory() throws {
    let root = try makeTree(["Tests/T.swift", "Tests/Fixtures/F.swift"])
    defer { try? FileManager.default.removeItem(at: root) }

    // A directory named on the command line is scanned even if its name matches.
    let files = try FileReader.findSwiftFiles(
        in: [root.appendingPathComponent("Tests").path],
        excluding: [ExcludePattern("Tests"), ExcludePattern("Fixtures")]
    )
    #expect(relative(files, to: root) == ["Tests/T.swift"])

    // A file named on the command line is skipped if it matches.
    let explicit = try FileReader.findSwiftFiles(
        in: [root.appendingPathComponent("Tests/T.swift").path],
        excluding: [ExcludePattern("T.swift")]
    )
    #expect(explicit.isEmpty)
}

@Test("extractElements(fromPaths:) reads every given path once")
func testExtractElementsFromPaths() throws {
    let root = try makeTree([])
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Skip"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "func a() {}".write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
    try "func b() {}".write(to: root.appendingPathComponent("Skip/B.swift"), atomically: true, encoding: .utf8)

    let extractor = CodeElementExtractor(configuration: .init(elementTypes: [.function]))
    let elements = try extractor.extractElements(
        fromPaths: [root.path, root.appendingPathComponent("A.swift").path],
        excluding: [ExcludePattern("Skip")]
    )
    #expect(elements.map(\.name) == ["a"])
}
