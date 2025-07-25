import SwiftSyntax
import SwiftParser
import Foundation

// MARK: - AST Parser

/// Provides Swift AST parsing functionality using SwiftSyntax.
public class SwiftASTParser {
    
    /// Parses a Swift source file and generates an AST.
    /// - Parameter path: The file path to parse
    /// - Returns: The parsed SourceFileSyntax
    /// - Throws: File reading errors
    public static func parseFile(at path: String) throws -> SourceFileSyntax {
        let url = URL(fileURLWithPath: path)
        let source = try String(contentsOf: url)
        return Parser.parse(source: source)
    }
    
    /// Parses Swift source code from a string and generates an AST.
    /// - Parameter source: The source code string to parse
    /// - Returns: The parsed SourceFileSyntax
    public static func parseSource(_ source: String) -> SourceFileSyntax {
        return Parser.parse(source: source)
    }
} 