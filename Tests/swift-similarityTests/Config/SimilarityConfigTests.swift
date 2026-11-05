import Testing
import Foundation
@testable import swift_similarity

// MARK: - Parsing

@Test("Parses the supported keys, comments and multi-line arrays")
func testParseSupportedKeys() throws {
    let config = try SimilarityConfig.parse("""
        # Project settings
        threshold = 0.85   # trailing comment
        element-type = "struct"
        exclude = [
          "Tests",            # tests
          '**/Generated/**',
        ]
        """)
    #expect(config.threshold == 0.85)
    #expect(config.elementType == "struct")
    #expect(config.exclude == ["Tests", "**/Generated/**"])
    #expect(config.unknownKeys.isEmpty)
}

@Test("Accepts snake_case keys, integers, a single exclude string and CRLF line endings")
func testParseVariants() throws {
    let config = try SimilarityConfig.parse("threshold = 1\r\nelement_type = \"all\"\r\nexclude = \"*.pb.swift\"\r\n")
    #expect(config.threshold == 1)
    #expect(config.elementType == "all")
    #expect(config.exclude == ["*.pb.swift"])
}

@Test("Collects unknown keys instead of failing")
func testParseUnknownKeys() throws {
    let config = try SimilarityConfig.parse("min_lines = 3\nthreshold = 0.7\nbody_only = true\n")
    #expect(config.threshold == 0.7)
    #expect(config.unknownKeys == ["min_lines", "body_only"])
}

@Test("Reports malformed files and wrong value types with a line number", arguments: [
    ("threshold = \"high\"", 1),
    ("\nelement_type = 3", 2),
    ("exclude = [1, 2]", 1),
    ("threshold 0.8", 1),
    ("threshold = 0.8 0.9", 1),
    ("exclude = [\"a\"", 1),
    ("name = \"unterminated", 1),
    ("\n\n[swift]\nthreshold = 0.8", 3),
    ("a.b = 1", 1),
    ("threshold =", 1),
])
func testParseErrors(text: String, line: Int) {
    #expect {
        try SimilarityConfig.parse(text)
    } throws: { error in
        (error as? SimilarityConfig.ParseError)?.line == line
    }
}

// MARK: - Discovery

@Test("find(from:) walks up parent directories to the nearest config file")
func testFindWalksUp() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-similarity-config-\(UUID().uuidString)")
    let nested = root.appendingPathComponent("a/b/c")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try "threshold = 0.5".write(to: root.appendingPathComponent(SimilarityConfig.fileName), atomically: true, encoding: .utf8)
    #expect(SimilarityConfig.find(from: nested)?.path == root.appendingPathComponent(SimilarityConfig.fileName).path)

    // A nearer file wins.
    let nearer = root.appendingPathComponent("a/b/\(SimilarityConfig.fileName)")
    try "threshold = 0.6".write(to: nearer, atomically: true, encoding: .utf8)
    let found = try #require(SimilarityConfig.find(from: nested))
    #expect(found.path == nearer.path)
    #expect(try SimilarityConfig.load(from: found).threshold == 0.6)
}

// MARK: - Precedence

@Test("Command-line values override the config file, which overrides the defaults")
func testSettingsPrecedence() {
    let config = SimilarityConfig(threshold: 0.6, elementType: "struct", exclude: ["Tests"])

    let defaults = ScanSettings.resolve(threshold: nil, elementType: nil, exclude: [], config: nil)
    #expect(defaults == ScanSettings(threshold: ScanSettings.defaultThreshold, elementType: ScanSettings.defaultElementType, exclude: []))

    let fromConfig = ScanSettings.resolve(threshold: nil, elementType: nil, exclude: [], config: config)
    #expect(fromConfig == ScanSettings(threshold: 0.6, elementType: "struct", exclude: ["Tests"]))

    let fromCLI = ScanSettings.resolve(threshold: 0.9, elementType: "all", exclude: ["*.pb.swift"], config: config)
    #expect(fromCLI == ScanSettings(threshold: 0.9, elementType: "all", exclude: ["Tests", "*.pb.swift"]))

    // A config file that sets only some keys leaves the rest at their defaults.
    let partial = ScanSettings.resolve(threshold: nil, elementType: nil, exclude: [], config: SimilarityConfig(threshold: 0.7))
    #expect(partial == ScanSettings(threshold: 0.7, elementType: ScanSettings.defaultElementType, exclude: []))
}
