import Foundation

// MARK: - Config File

/// Settings read from a `similarity.toml` file.
///
/// The file is a small subset of TOML: top-level `key = value` lines, `#` comments, and values
/// that are strings, numbers, booleans or arrays of strings (which may span lines). Keys may use
/// `_` or `-`. Supported keys:
///
/// ```toml
/// threshold = 0.85            # --threshold
/// element_type = "function"   # --element-type
/// exclude = ["Tests", "**/Generated/**"]  # added to --exclude
/// min_lines = 5               # --min-lines
/// min_tokens = 0              # --min-tokens
/// body_only = false           # --body-only / --no-body-only
/// ignore_directives = true    # --ignore-directives / --no-ignore-directives
/// sort = "similarity"         # --sort
/// fail_on_duplicates = false  # --fail-on-duplicates / --no-fail-on-duplicates
/// rename_cost = 1.0           # --rename-cost
/// compare = "tree"           # --compare ("tree", "members" or "witnesses")
/// group = false              # --group / --no-group
/// ```
///
/// `no_ignore_directives = true`, mirroring the `--no-ignore-directives` flag, is accepted as the
/// opposite of `ignore_directives`.
///
/// The same type holds the options given on the command line, where nil means "not given".
public struct SimilarityConfig: Equatable, Sendable {
    /// The file name looked up by `find(from:)`.
    public static let fileName = "similarity.toml"

    public var threshold: Double?
    public var elementType: String?
    public var exclude: [String] = []
    public var minLines: Int?
    public var minTokens: Int?
    public var bodyOnly: Bool?
    public var ignoreDirectives: Bool?
    public var sort: String?
    public var failOnDuplicates: Bool?
    public var renameCost: Double?
    public var compare: String?
    public var group: Bool?
    /// Keys the file sets that are not supported, for warnings.
    public var unknownKeys: [String] = []

    public init(
        threshold: Double? = nil,
        elementType: String? = nil,
        exclude: [String] = [],
        minLines: Int? = nil,
        minTokens: Int? = nil,
        bodyOnly: Bool? = nil,
        ignoreDirectives: Bool? = nil,
        sort: String? = nil,
        failOnDuplicates: Bool? = nil,
        renameCost: Double? = nil,
        compare: String? = nil,
        group: Bool? = nil
    ) {
        self.renameCost = renameCost
        self.compare = compare
        self.group = group
        self.threshold = threshold
        self.elementType = elementType
        self.exclude = exclude
        self.minLines = minLines
        self.minTokens = minTokens
        self.bodyOnly = bodyOnly
        self.ignoreDirectives = ignoreDirectives
        self.sort = sort
        self.failOnDuplicates = failOnDuplicates
    }

    /// An error in a config file, with the line it was found on.
    public struct ParseError: Error, LocalizedError, Equatable {
        public let line: Int
        public let message: String
        public var errorDescription: String? { "line \(line): \(message)" }
    }

    /// Finds the nearest `similarity.toml` in `directory` or one of its parents.
    public static func find(from directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let candidate = current.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    /// Reads and parses a config file.
    /// - Throws: File reading errors or `ParseError`
    public static func load(from url: URL) throws -> SimilarityConfig {
        try parse(String(contentsOf: url, encoding: .utf8))
    }

    /// Parses the contents of a config file.
    /// - Throws: `ParseError` for malformed TOML or a value of the wrong type
    public static func parse(_ text: String) throws -> SimilarityConfig {
        var config = SimilarityConfig()
        var parser = TOMLSubsetParser(text)
        while let (key, value, line) = try parser.nextEntry() {
            func string() throws -> String {
                guard case .string(let string) = value else {
                    throw ParseError(line: line, message: "'\(key)' must be a string")
                }
                return string
            }
            // similarity-ignore: one type check per TOML value kind, like string()
            func bool() throws -> Bool {
                guard case .bool(let bool) = value else {
                    throw ParseError(line: line, message: "'\(key)' must be true or false")
                }
                return bool
            }
            func count() throws -> Int {
                guard case .number(let number) = value, number >= 0, number == number.rounded(), number <= Double(Int32.max) else {
                    throw ParseError(line: line, message: "'\(key)' must be a whole number, 0 or more")
                }
                return Int(number)
            }
            switch key.replacingOccurrences(of: "-", with: "_") {
            case "threshold":
                guard case .number(let number) = value else {
                    throw ParseError(line: line, message: "'\(key)' must be a number")
                }
                config.threshold = number
            case "element_type":
                config.elementType = try string()
            case "min_lines":
                config.minLines = try count()
            case "min_tokens":
                config.minTokens = try count()
            case "body_only":
                config.bodyOnly = try bool()
            case "ignore_directives":
                config.ignoreDirectives = try bool()
            case "no_ignore_directives":
                config.ignoreDirectives = try !bool()
            case "sort":
                config.sort = try string()
            case "fail_on_duplicates":
                config.failOnDuplicates = try bool()
            case "rename_cost":
                guard case .number(let number) = value else {
                    throw ParseError(line: line, message: "'\(key)' must be a number")
                }
                config.renameCost = number
            case "compare":
                config.compare = try string()
            case "group":
                config.group = try bool()
            case "exclude":
                switch value {
                case .string(let string):
                    config.exclude = [string]
                case .array(let strings):
                    config.exclude = strings
                default:
                    throw ParseError(line: line, message: "'\(key)' must be an array of strings")
                }
            default:
                config.unknownKeys.append(key)
            }
        }
        return config
    }
}

// MARK: - Settings Resolution

/// Scan settings after combining command-line options, the config file and built-in defaults.
public struct ScanSettings: Equatable, Sendable {
    public static let defaultThreshold = 0.8
    public static let defaultElementType = "function"
    public static let defaultMinLines = 5
    public static let defaultMinTokens = 0
    public static let defaultSort = "similarity"
    /// Cost of renaming (relabeling) a node, as in the TSED paper (arXiv:2404.08817).
    public static let defaultRenameCost = 1.0
    public static let defaultCompare = "tree"
    /// The element type used with `compare = "members"` when none is given: every kind of type.
    public static let defaultMemberElementType = "all"
    /// The element type used with `compare = "witnesses"` when none is given: every kind of member.
    public static let defaultWitnessElementType = "all"
    /// The minimum lines used with `compare = "witnesses"` when none is given: none, since
    /// implementations of a requirement are often one-liners worth sharing.
    public static let defaultWitnessMinLines = 0

    public var threshold: Double
    public var elementType: String
    /// Config file patterns followed by command-line patterns.
    public var exclude: [String]
    public var minLines: Int
    public var minTokens: Int
    public var bodyOnly: Bool
    public var ignoreDirectives: Bool
    public var sort: String
    public var failOnDuplicates: Bool
    /// Cost of a node rename in the tree edit distance; insertions and deletions cost 1.
    public var renameCost: Double
    /// What is compared: "tree" (whole syntax trees, TSED), "members" (members of types) or
    /// "witnesses" (bodies of implementations of the same protocol requirement).
    public var compare: String
    /// Report groups of mutually similar declarations instead of a flat list of pairs.
    public var group: Bool

    public init(
        threshold: Double = defaultThreshold,
        elementType: String = defaultElementType,
        exclude: [String] = [],
        minLines: Int = defaultMinLines,
        minTokens: Int = defaultMinTokens,
        bodyOnly: Bool = false,
        ignoreDirectives: Bool = true,
        sort: String = defaultSort,
        failOnDuplicates: Bool = false,
        renameCost: Double = defaultRenameCost,
        compare: String = defaultCompare,
        group: Bool = false
    ) {
        self.renameCost = renameCost
        self.compare = compare
        self.group = group
        self.threshold = threshold
        self.elementType = elementType
        self.exclude = exclude
        self.minLines = minLines
        self.minTokens = minTokens
        self.bodyOnly = bodyOnly
        self.ignoreDirectives = ignoreDirectives
        self.sort = sort
        self.failOnDuplicates = failOnDuplicates
    }

    /// Combines settings: a value given on the command line wins over the config file, which wins
    /// over the default. Exclude patterns from both are used.
    public static func resolve(commandLine: SimilarityConfig, file: SimilarityConfig?) -> ScanSettings {
        let defaults = ScanSettings()
        let compare = commandLine.compare ?? file?.compare ?? defaults.compare
        // Members are compared between types, so that mode defaults to every kind of type, and
        // witnesses to every kind of member; witnesses are often short, so any length counts.
        let defaultElementType: String
        let defaultMinLines: Int
        switch compare.lowercased() {
        case "members":
            (defaultElementType, defaultMinLines) = (defaultMemberElementType, defaults.minLines)
        case "witnesses":
            (defaultElementType, defaultMinLines) = (defaultWitnessElementType, defaultWitnessMinLines)
        default:
            (defaultElementType, defaultMinLines) = (defaults.elementType, defaults.minLines)
        }
        return ScanSettings(
            threshold: commandLine.threshold ?? file?.threshold ?? defaults.threshold,
            elementType: commandLine.elementType ?? file?.elementType ?? defaultElementType,
            exclude: (file?.exclude ?? []) + commandLine.exclude,
            minLines: commandLine.minLines ?? file?.minLines ?? defaultMinLines,
            minTokens: commandLine.minTokens ?? file?.minTokens ?? defaults.minTokens,
            bodyOnly: commandLine.bodyOnly ?? file?.bodyOnly ?? defaults.bodyOnly,
            ignoreDirectives: commandLine.ignoreDirectives ?? file?.ignoreDirectives ?? defaults.ignoreDirectives,
            sort: commandLine.sort ?? file?.sort ?? defaults.sort,
            failOnDuplicates: commandLine.failOnDuplicates ?? file?.failOnDuplicates ?? defaults.failOnDuplicates,
            renameCost: commandLine.renameCost ?? file?.renameCost ?? defaults.renameCost,
            compare: compare,
            group: commandLine.group ?? file?.group ?? defaults.group
        )
    }

    /// Tree edit operation costs for these settings: unit insertion and deletion, `renameCost` renames.
    public var operationCosts: APTED.OperationCosts {
        APTED.OperationCosts(insertion: 1.0, deletion: 1.0, substitution: renameCost)
    }
}

// MARK: - TOML Subset Parser

private enum TOMLValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([String])
}

private struct TOMLSubsetParser {
    private let chars: [Character]
    private var index = 0
    private var line = 1

    init(_ text: String) {
        // "\r\n" is a single Character in Swift; make every line end in "\n".
        chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    /// The next `key = value` entry, or nil at the end of the input.
    mutating func nextEntry() throws -> (String, TOMLValue, Int)? {
        skipBlankLines()
        guard let char = peek() else { return nil }
        if char == "[" {
            throw error("tables are not supported; put keys at the top level")
        }
        let entryLine = line
        let key = try parseKey()
        skipSpaces()
        guard peek() == "=" else { throw error("expected '=' after '\(key)'") }
        index += 1
        skipSpaces()
        let value = try parseValue()
        skipSpaces()
        skipComment()
        if let next = peek(), next != "\n" {
            throw error("unexpected '\(next)' after the value of '\(key)'")
        }
        return (key, value, entryLine)
    }

    private func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private func error(_ message: String) -> SimilarityConfig.ParseError {
        SimilarityConfig.ParseError(line: line, message: message)
    }

    private mutating func skipSpaces() {
        while let char = peek(), char == " " || char == "\t" || char == "\r" {
            index += 1
        }
    }

    private mutating func skipComment() {
        if peek() == "#" {
            while let char = peek(), char != "\n" {
                index += 1
            }
        }
    }

    /// Skips whitespace, newlines and comments.
    private mutating func skipBlankLines() {
        while true {
            skipSpaces()
            skipComment()
            guard peek() == "\n" else { return }
            index += 1
            line += 1
        }
    }

    private mutating func parseKey() throws -> String {
        if peek() == "\"" || peek() == "'" {
            return try parseString()
        }
        var key = ""
        while let char = peek(), char.isLetter || char.isNumber || char == "_" || char == "-" {
            key.append(char)
            index += 1
        }
        guard !key.isEmpty else {
            throw error(peek() == "." ? "dotted keys are not supported" : "expected a key")
        }
        if peek() == "." {
            throw error("dotted keys are not supported")
        }
        return key
    }

    private mutating func parseValue() throws -> TOMLValue {
        switch peek() {
        case "\"", "'":
            return .string(try parseString())
        case "[":
            return .array(try parseArray())
        case nil, "\n", "#":
            throw error("expected a value")
        default:
            var token = ""
            let terminators: Set<Character> = [" ", "\t", "\r", "\n", "#", ",", "]"]
            while let char = peek(), !terminators.contains(char) {
                token.append(char)
                index += 1
            }
            if token == "true" { return .bool(true) }
            if token == "false" { return .bool(false) }
            if let number = Double(token.replacingOccurrences(of: "_", with: "")) {
                return .number(number)
            }
            throw error("invalid value '\(token)'")
        }
    }

    private mutating func parseString() throws -> String {
        let quote = chars[index]
        // Multi-line strings are not supported.
        if index + 2 < chars.count, chars[index + 1] == quote, chars[index + 2] == quote {
            throw error("multi-line strings are not supported")
        }
        index += 1
        var result = ""
        while let char = peek() {
            index += 1
            if char == quote {
                return result
            }
            if char == "\n" {
                break
            }
            if char == "\\" && quote == "\"" {
                guard let escaped = peek() else { break }
                index += 1
                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                default: throw error("unsupported escape '\\\(escaped)'")
                }
            } else {
                result.append(char)
            }
        }
        throw error("unterminated string")
    }

    private mutating func parseArray() throws -> [String] {
        index += 1 // [
        var items: [String] = []
        while true {
            skipBlankLines()
            if peek() == "]" {
                index += 1
                return items
            }
            guard peek() == "\"" || peek() == "'" else {
                throw error(peek() == nil ? "unterminated array" : "arrays may only contain strings")
            }
            items.append(try parseString())
            skipBlankLines()
            switch peek() {
            case ",":
                index += 1
            case "]":
                continue
            default:
                throw error("expected ',' or ']' in array")
            }
        }
    }
}
