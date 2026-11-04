import SwiftSyntax
import SwiftParser
import Foundation

// MARK: - Code Element Types

/// Represents a type of code element that can be extracted
public enum CodeElementType: String, CaseIterable, Sendable {
    case function = "function"
    case `struct` = "struct"
    case `class` = "class"
    case `enum` = "enum"
}

/// Represents an extracted code element with location information
public struct CodeElement: Sendable {
    /// The type of this code element
    public let elementType: CodeElementType
    /// The name of the element
    public let name: String
    /// The signature or full declaration
    public let signature: String
    /// Source file path
    public let filePath: String
    /// Starting line number (1-indexed)
    public let startLine: Int
    /// Ending line number (1-indexed)
    public let endLine: Int
    /// Preview of the code (first few lines)
    public let codePreview: String
    /// The tree node representation for similarity calculation
    public let treeNode: TreeNode
    /// UTF-8 byte range of the declaration in its file (excluding trivia), if known
    public let byteRange: Range<Int>?
    
    /// Creates a code element
    public init(elementType: CodeElementType, name: String, signature: String, filePath: String, startLine: Int, endLine: Int, codePreview: String, treeNode: TreeNode, byteRange: Range<Int>? = nil) {
        self.elementType = elementType
        self.name = name
        self.signature = signature
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.codePreview = codePreview
        self.treeNode = treeNode
        self.byteRange = byteRange
    }
    
    /// Whether one of the two elements is declared inside the other (e.g. a class and its method,
    /// or a function and a nested function). Such pairs share source code, so comparing them is
    /// meaningless.
    public func isNested(with other: CodeElement) -> Bool {
        guard filePath == other.filePath else { return false }
        if let range = byteRange, let otherRange = other.byteRange {
            return range.contains(otherRange) || otherRange.contains(range)
        }
        // Without byte ranges, fall back to line ranges (may also match elements sharing lines)
        let contains = startLine <= other.startLine && other.endLine <= endLine
        let isContained = other.startLine <= startLine && endLine <= other.endLine
        return contains || isContained
    }
}

private extension Range where Bound == Int {
    func contains(_ other: Range<Int>) -> Bool {
        lowerBound <= other.lowerBound && other.upperBound <= upperBound
    }
}

// MARK: - Code Element Extractor

/// Extracts code elements from Swift source files using SwiftSyntax
public class CodeElementExtractor {
    
    /// Configuration for code element extraction
    public struct Configuration {
        /// Types of elements to extract
        public let elementTypes: Set<CodeElementType>
        /// Maximum lines for code preview
        public let maxPreviewLines: Int
        
        /// Creates extraction configuration
        /// - Parameters:
        ///   - elementTypes: Types to extract (default: all)
        ///   - maxPreviewLines: Max preview lines (default: 5)
        public init(elementTypes: Set<CodeElementType> = Set(CodeElementType.allCases), maxPreviewLines: Int = 5) {
            self.elementTypes = elementTypes
            self.maxPreviewLines = maxPreviewLines
        }
    }
    
    /// Configuration for this extractor
    public let configuration: Configuration
    
    /// Creates a code element extractor
    /// - Parameter configuration: Extraction configuration
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    /// Extracts code elements from a Swift file
    /// - Parameter filePath: Path to the Swift file
    /// - Returns: Array of extracted code elements
    /// - Throws: File reading or parsing errors
    public func extractElements(from filePath: String) throws -> [CodeElement] {
        let sourceFile = try SwiftASTParser.parseFile(at: filePath)
        let sourceContent = try String(contentsOf: URL(fileURLWithPath: filePath))
        let sourceLines = sourceContent.components(separatedBy: .newlines)
        
        let visitor = CodeElementVisitor(
            filePath: filePath,
            sourceLines: sourceLines,
            sourceContent: sourceContent,
            sourceFile: sourceFile,
            configuration: configuration
        )
        
        visitor.walk(sourceFile)
        return visitor.extractedElements
    }
    
    /// Extracts code elements from a directory
    /// - Parameter directoryPath: Path to directory containing Swift files
    /// - Returns: Array of all extracted code elements
    /// - Throws: File system or parsing errors
    public func extractElements(fromDirectory directoryPath: String) throws -> [CodeElement] {
        let swiftFiles = try FileReader.findSwiftFiles(in: directoryPath)
        var allElements: [CodeElement] = []
        
        for filePath in swiftFiles {
            let elements = try extractElements(from: filePath)
            allElements.append(contentsOf: elements)
        }
        
        return allElements
    }
}

// MARK: - Code Element Visitor

/// SwiftSyntax visitor that extracts code elements
private class CodeElementVisitor: SyntaxVisitor {
    let filePath: String
    let sourceLines: [String]
    let sourceContent: String
    let sourceFile: SourceFileSyntax
    let configuration: CodeElementExtractor.Configuration
    let locationConverter: SourceLocationConverter
    var extractedElements: [CodeElement] = []
    
    init(filePath: String, sourceLines: [String], sourceContent: String, sourceFile: SourceFileSyntax, configuration: CodeElementExtractor.Configuration) {
        self.filePath = filePath
        self.sourceLines = sourceLines
        self.sourceContent = sourceContent
        self.sourceFile = sourceFile
        self.configuration = configuration
        self.locationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }
    
    // Visit function declarations
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if configuration.elementTypes.contains(.function) {
            if let element = createCodeElement(from: node, type: .function) {
                extractedElements.append(element)
            }
        }
        return .visitChildren
    }
    
    // Visit struct declarations
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if configuration.elementTypes.contains(.struct) {
            if let element = createCodeElement(from: node, type: .struct) {
                extractedElements.append(element)
            }
        }
        return .visitChildren
    }
    
    // Visit class declarations
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if configuration.elementTypes.contains(.class) {
            if let element = createCodeElement(from: node, type: .class) {
                extractedElements.append(element)
            }
        }
        return .visitChildren
    }
    
    // Visit enum declarations
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if configuration.elementTypes.contains(.enum) {
            if let element = createCodeElement(from: node, type: .enum) {
                extractedElements.append(element)
            }
        }
        return .visitChildren
    }
    
    // Create code element from syntax node
    private func createCodeElement(from node: some DeclSyntaxProtocol, type: CodeElementType) -> CodeElement? {
        // Get name
        guard let name = extractName(from: node) else { return nil }
        
        // Create signature (simplified - just the node description)
        let signature = node.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Calculate actual line numbers
        let (startLine, endLine) = calculateLineNumbers(for: node)
        
        // Create code preview from actual source lines
        let codePreview = extractCodePreview(startLine: startLine, endLine: endLine)
        
        // Create tree node for similarity calculation
        let treeNode = ASTToTreeConverter.convertSyntaxNode(node)
        
        return CodeElement(
            elementType: type,
            name: name,
            signature: signature,
            filePath: filePath,
            startLine: startLine,
            endLine: endLine,
            codePreview: codePreview,
            treeNode: treeNode,
            byteRange: node.positionAfterSkippingLeadingTrivia.utf8Offset..<node.endPositionBeforeTrailingTrivia.utf8Offset
        )
    }
    
    // Extract name from declaration
    private func extractName(from node: some DeclSyntaxProtocol) -> String? {
        if let funcDecl = node.as(FunctionDeclSyntax.self) {
            return funcDecl.name.text
        } else if let structDecl = node.as(StructDeclSyntax.self) {
            return structDecl.name.text
        } else if let classDecl = node.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        } else if let enumDecl = node.as(EnumDeclSyntax.self) {
            return enumDecl.name.text
        }
        return nil
    }
    
    // Calculate 1-indexed line numbers for a syntax node, excluding leading and trailing trivia.
    // SourceLocationConverter works on UTF-8 offsets, so multi-byte characters
    // (e.g. Japanese comments) before the node do not shift the result.
    private func calculateLineNumbers(for node: some SyntaxProtocol) -> (startLine: Int, endLine: Int) {
        let startLine = node.startLocation(converter: locationConverter).line
        let endLine = node.endLocation(converter: locationConverter).line
        
        return (startLine: startLine, endLine: endLine)
    }
    
    // Extract code preview from source lines
    private func extractCodePreview(startLine: Int, endLine: Int) -> String {
        let actualStartLine = max(1, startLine) - 1 // Convert to 0-indexed
        let actualEndLine = min(sourceLines.count, endLine) - 1
        let maxLines = min(configuration.maxPreviewLines, actualEndLine - actualStartLine + 1)
        
        guard actualStartLine < sourceLines.count else {
            return ""
        }
        
        let endIndex = min(actualStartLine + maxLines, sourceLines.count)
        let previewLines = Array(sourceLines[actualStartLine..<endIndex])
        return previewLines.joined(separator: "\n")
    }
}