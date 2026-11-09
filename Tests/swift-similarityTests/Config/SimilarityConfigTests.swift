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
    let config = try SimilarityConfig.parse("min_size = 3\nthreshold = 0.7\nverbose = true\n")
    #expect(config.threshold == 0.7)
    #expect(config.unknownKeys == ["min_size", "verbose"])
}

@Test("Parses the filtering and reporting keys")
func testParseFilteringAndReportingKeys() throws {
    let config = try SimilarityConfig.parse("""
        min_lines = 10
        min-tokens = 30
        body_only = true
        ignore_directives = false
        sort = "priority"
        fail-on-duplicates = true
        """)
    #expect(config == SimilarityConfig(
        minLines: 10,
        minTokens: 30,
        bodyOnly: true,
        ignoreDirectives: false,
        sort: "priority",
        failOnDuplicates: true
    ))
    #expect(config.unknownKeys.isEmpty)
    
    // The key mirroring the --no-ignore-directives flag is the opposite of ignore_directives.
    #expect(try SimilarityConfig.parse("no_ignore_directives = true").ignoreDirectives == false)
    #expect(try SimilarityConfig.parse("no-ignore-directives = false").ignoreDirectives == true)
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
    ("min_lines = -1", 1),
    ("min_tokens = 2.5", 1),
    ("min_lines = \"5\"", 1),
    ("body_only = 1", 1),
    ("\nfail_on_duplicates = \"yes\"", 2),
    ("sort = 1", 1),
    ("rename_cost = \"low\"", 1),
])
func testParseErrors(text: String, line: Int) {
    #expect {
        try SimilarityConfig.parse(text)
    } throws: { error in
        (error as? SimilarityConfig.ParseError)?.line == line
    }
}

@Test("Reads rename_cost and resolves it into operation costs")
func testRenameCost() throws {
    let config = try SimilarityConfig.parse("rename-cost = 0.3\n")
    #expect(config.renameCost == 0.3)

    let defaults = ScanSettings.resolve(commandLine: SimilarityConfig(), file: nil)
    #expect(defaults.renameCost == ScanSettings.defaultRenameCost)
    #expect(defaults.operationCosts == APTED.OperationCosts())

    let fromFile = ScanSettings.resolve(commandLine: SimilarityConfig(), file: config)
    #expect(fromFile.operationCosts == APTED.OperationCosts(insertion: 1, deletion: 1, substitution: 0.3))

    let fromCLI = ScanSettings.resolve(commandLine: SimilarityConfig(renameCost: 0.5), file: config)
    #expect(fromCLI.renameCost == 0.5)
}

@Test("Groups by default; the file and the command line can turn it off")
func testGroupSetting() throws {
    let config = try SimilarityConfig.parse("group = false\n")
    #expect(config.group == false)
    #expect(ScanSettings.resolve(commandLine: SimilarityConfig(), file: nil).group == true)
    #expect(ScanSettings.resolve(commandLine: SimilarityConfig(), file: config).group == false)
    #expect(ScanSettings.resolve(commandLine: SimilarityConfig(group: true), file: config).group == true)
}

@Test("Reads compare, and members mode defaults the element type to all types")
func testCompareMode() throws {
    let config = try SimilarityConfig.parse("compare = \"members\"\n")
    #expect(config.compare == "members")

    let defaults = ScanSettings.resolve(commandLine: SimilarityConfig(), file: nil)
    #expect(defaults.compare == "tree")
    #expect(defaults.elementType == ScanSettings.defaultElementType)

    let members = ScanSettings.resolve(commandLine: SimilarityConfig(), file: config)
    #expect(members.compare == "members")
    #expect(members.elementType == "all")

    // An element type given anywhere wins over the members default.
    let structs = ScanSettings.resolve(commandLine: SimilarityConfig(elementType: "struct"), file: config)
    #expect(structs.elementType == "struct")
    let tree = ScanSettings.resolve(commandLine: SimilarityConfig(compare: "tree"), file: config)
    #expect(tree.elementType == ScanSettings.defaultElementType)
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

@Test("find(from:) stops at the root directory")
func testFindStopsAtRoot() throws {
    let root = URL(fileURLWithPath: "/")
    try #require(!FileManager.default.fileExists(atPath: root.appendingPathComponent(SimilarityConfig.fileName).path))
    #expect(SimilarityConfig.find(from: root) == nil)

    let nested = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-similarity-config-\(UUID().uuidString)/a")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: nested.deletingLastPathComponent()) }
    #expect(SimilarityConfig.find(from: nested) == nil)
}

// MARK: - Precedence

@Test("Command-line values override the config file, which overrides the defaults")
func testSettingsPrecedence() {
    let file = SimilarityConfig(threshold: 0.6, elementType: "struct", exclude: ["Tests"])
    
    let defaults = ScanSettings.resolve(commandLine: SimilarityConfig(), file: nil)
    #expect(defaults == ScanSettings())
    #expect(defaults.threshold == 0.8 && defaults.elementType == "function" && defaults.minLines == 5)
    #expect(defaults.ignoreDirectives && !defaults.bodyOnly && !defaults.failOnDuplicates && defaults.sort == "similarity")
    
    let fromFile = ScanSettings.resolve(commandLine: SimilarityConfig(), file: file)
    #expect(fromFile == ScanSettings(threshold: 0.6, elementType: "struct", exclude: ["Tests"]))
    
    let commandLine = SimilarityConfig(threshold: 0.9, elementType: "all", exclude: ["*.pb.swift"])
    let fromCLI = ScanSettings.resolve(commandLine: commandLine, file: file)
    #expect(fromCLI == ScanSettings(threshold: 0.9, elementType: "all", exclude: ["Tests", "*.pb.swift"]))
    
    // A config file that sets only some keys leaves the rest at their defaults.
    let partial = ScanSettings.resolve(commandLine: SimilarityConfig(), file: SimilarityConfig(threshold: 0.7))
    #expect(partial == ScanSettings(threshold: 0.7))
}

@Test("Filtering and reporting options follow the same precedence, including turning flags off")
func testFilteringAndReportingPrecedence() {
    let file = SimilarityConfig(
        minLines: 10,
        minTokens: 30,
        bodyOnly: true,
        ignoreDirectives: false,
        sort: "priority",
        failOnDuplicates: true
    )
    
    let fromFile = ScanSettings.resolve(commandLine: SimilarityConfig(), file: file)
    #expect(fromFile == ScanSettings(
        minLines: 10, minTokens: 30, bodyOnly: true, ignoreDirectives: false, sort: "priority", failOnDuplicates: true
    ))
    
    // --min-lines 0 --min-tokens 0 --no-body-only --ignore-directives --sort similarity --no-fail-on-duplicates
    let commandLine = SimilarityConfig(
        minLines: 0,
        minTokens: 0,
        bodyOnly: false,
        ignoreDirectives: true,
        sort: "similarity",
        failOnDuplicates: false
    )
    let fromCLI = ScanSettings.resolve(commandLine: commandLine, file: file)
    #expect(fromCLI == ScanSettings(minLines: 0, minTokens: 0))
    
    // Options not given on the command line still come from the file.
    let mixed = ScanSettings.resolve(commandLine: SimilarityConfig(minLines: 3, failOnDuplicates: false), file: file)
    #expect(mixed == ScanSettings(
        minLines: 3, minTokens: 30, bodyOnly: true, ignoreDirectives: false, sort: "priority", failOnDuplicates: false
    ))
}
