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
/// ```
public struct SimilarityConfig: Equatable, Sendable {
    /// The file name looked up by `find(from:)`.
    public static let fileName = "similarity.toml"

    public var threshold: Double?
    public var elementType: String?
    public var exclude: [String] = []
    /// Keys the file sets that are not supported, for warnings.
    public var unknownKeys: [String] = []

    public init(threshold: Double? = nil, elementType: String? = nil, exclude: [String] = []) {
        self.threshold = threshold
        self.elementType = elementType
        self.exclude = exclude
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
            switch key.replacingOccurrences(of: "-", with: "_") {
            case "threshold":
                guard case .number(let number) = value else {
                    throw ParseError(line: line, message: "'\(key)' must be a number")
                }
                config.threshold = number
            case "element_type":
                guard case .string(let string) = value else {
                    throw ParseError(line: line, message: "'\(key)' must be a string")
                }
                config.elementType = string
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

    public var threshold: Double
    public var elementType: String
    /// Config file patterns followed by command-line patterns.
    public var exclude: [String]

    /// Combines settings: a command-line value wins over the config file, which wins over the
    /// default. Exclude patterns from both are used.
    public static func resolve(
        threshold: Double?,
        elementType: String?,
        exclude: [String],
        config: SimilarityConfig?
    ) -> ScanSettings {
        ScanSettings(
            threshold: threshold ?? config?.threshold ?? defaultThreshold,
            elementType: elementType ?? config?.elementType ?? defaultElementType,
            exclude: (config?.exclude ?? []) + exclude
        )
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
