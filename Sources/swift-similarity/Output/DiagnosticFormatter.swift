import Foundation

// MARK: - Diagnostic Output

/// Formats similar pairs as compiler-style diagnostics that tools show next to the code:
/// Xcode (`scan --format xcode`) and GitHub Actions annotations (`--format github`).
///
/// Each declaration that has similar declarations gets one warning at its first line, naming the
/// declarations it is similar to (most similar first). Pairs are not listed one by one, so a
/// declaration with several copies is flagged once instead of once per copy.
public enum DiagnosticFormatter {
    /// The diagnostic syntax.
    public enum Style: String, CaseIterable, Sendable {
        /// `path:line:column: warning: message`, shown by Xcode in the editor and the issue navigator
        /// when printed by a Run Script build phase (and understood by most editors and CI logs).
        case xcode
        /// `::warning file=path,line=start,endLine=end,title=...::message`, a GitHub Actions
        /// workflow command that annotates the lines in the pull request diff.
        case github
    }

    /// At most this many similar declarations are named in one message; the rest are counted.
    public static let maximumNamedMatches = 5

    /// One line per declaration with similar declarations, ordered by file path and line.
    /// - Parameters:
    ///   - relativeTo: Paths of the annotated declarations under this directory are written
    ///     relative to it (GitHub resolves annotation paths against the repository root); nil keeps
    ///     them as they are (Xcode opens absolute paths).
    ///   - messagePathsRelativeTo: The same for the paths of similar declarations named in messages,
    ///     to keep messages short.
    public static func format(
        _ pairs: [(CodeElement, CodeElement, Double)],
        style: Style,
        relativeTo baseDirectory: String? = nil,
        messagePathsRelativeTo messageBaseDirectory: String? = nil
    ) -> String {
        var matches: [ElementIdentity: (element: CodeElement, others: [(CodeElement, Double)])] = [:]
        for (first, second, similarity) in pairs {
            matches[ElementIdentity(first), default: (first, [])].others.append((second, similarity))
            matches[ElementIdentity(second), default: (second, [])].others.append((first, similarity))
        }
        let declarations = matches.values.sorted {
            ($0.element.filePath, $0.element.startLine, $0.element.name) < ($1.element.filePath, $1.element.startLine, $1.element.name)
        }
        return declarations.map { declaration in
            let path = displayPath(declaration.element.filePath, relativeTo: baseDirectory)
            let message = message(for: declaration.element, others: declaration.others, relativeTo: messageBaseDirectory)
            switch style {
            case .xcode:
                return "\(path):\(declaration.element.startLine):1: warning: \(message)"
            case .github:
                let properties = [
                    "file=\(escapeProperty(path))",
                    "line=\(declaration.element.startLine)",
                    "endLine=\(declaration.element.endLine)",
                    "title=\(escapeProperty("Similar code (swift-similarity)"))",
                ]
                return "::warning \(properties.joined(separator: ","))::\(escapeData(message))"
            }
        }.joined(separator: "\n")
    }

    /// "`a` is similar to `b` (Foo.swift:40, 92.0%), ... [swift-similarity]"
    static func message(for element: CodeElement, others: [(CodeElement, Double)], relativeTo baseDirectory: String?) -> String {
        let sorted = others.sorted {
            ($1.1, $0.0.filePath, $0.0.startLine) < ($0.1, $1.0.filePath, $1.0.startLine)
        }
        let named = sorted.prefix(maximumNamedMatches).map { other, similarity in
            let location = other.filePath == element.filePath
                ? "line \(other.startLine)"
                : "\(displayPath(other.filePath, relativeTo: baseDirectory)):\(other.startLine)"
            return "\(other.elementType.rawValue) \(other.name) (\(location), \(String(format: "%.1f%%", similarity * 100)))"
        }
        var text = "\(element.elementType.rawValue) \(element.name) is similar to " + named.joined(separator: ", ")
        if sorted.count > maximumNamedMatches {
            text += " and \(sorted.count - maximumNamedMatches) more"
        }
        return text + " [swift-similarity]"
    }

    private static func displayPath(_ path: String, relativeTo baseDirectory: String?) -> String {
        guard let baseDirectory else { return path }
        let base = baseDirectory.hasSuffix("/") ? baseDirectory : baseDirectory + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    /// Escaping for the message of a GitHub workflow command.
    static func escapeData(_ text: String) -> String {
        text.replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    /// Escaping for a property value of a GitHub workflow command.
    static func escapeProperty(_ text: String) -> String {
        escapeData(text)
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: ",", with: "%2C")
    }
}
