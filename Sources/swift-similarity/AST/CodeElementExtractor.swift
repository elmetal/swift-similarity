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
    case initializer = "init"
    case actor = "actor"
    case `protocol` = "protocol"
    case `extension` = "extension"
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
public final class CodeElementExtractor: Sendable {
    
    /// Configuration for code element extraction
    public struct Configuration: Sendable {
        /// Types of elements to extract
        public let elementTypes: Set<CodeElementType>
        /// Maximum lines for code preview
        public let maxPreviewLines: Int
        /// Declarations spanning fewer source lines are skipped (0 keeps all).
        public let minLines: Int
        /// Declarations whose compared syntax has fewer tokens are skipped (0 keeps all).
        /// With `compareBodyOnly`, only the body's tokens are counted.
        public let minTokens: Int
        /// Skip declarations preceded by a comment containing `similarity-ignore`.
        public let respectIgnoreDirectives: Bool
        /// Compare only the body: the code block of functions and initializers, the member block
        /// of types and extensions. Names, attributes, modifiers, signatures and inheritance
        /// clauses are left out. Declarations without a body (protocol requirements) are skipped.
        public let compareBodyOnly: Bool

        /// Creates extraction configuration
        /// - Parameters:
        ///   - elementTypes: Types to extract (default: all)
        ///   - maxPreviewLines: Max preview lines (default: 5)
        ///   - minLines: Minimum declaration length in lines (default: 0, no limit)
        ///   - minTokens: Minimum number of tokens (default: 0, no limit)
        ///   - respectIgnoreDirectives: Honor `similarity-ignore` comments (default: true)
        ///   - compareBodyOnly: Compare bodies only (default: false)
        public init(
            elementTypes: Set<CodeElementType> = Set(CodeElementType.allCases),
            maxPreviewLines: Int = 5,
            minLines: Int = 0,
            minTokens: Int = 0,
            respectIgnoreDirectives: Bool = true,
            compareBodyOnly: Bool = false
        ) {
            self.elementTypes = elementTypes
            self.maxPreviewLines = maxPreviewLines
            self.minLines = minLines
            self.minTokens = minTokens
            self.respectIgnoreDirectives = respectIgnoreDirectives
            self.compareBodyOnly = compareBodyOnly
        }
    }

    /// The comment marker that excludes the declaration following it.
    public static let ignoreDirective = "similarity-ignore"
    
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
        let sourceContent = try String(contentsOf: URL(fileURLWithPath: filePath))
        let sourceFile = SwiftASTParser.parseSource(sourceContent)
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
        try extractElements(fromFiles: FileReader.findSwiftFiles(in: directoryPath))
    }

    /// Extracts code elements from directories and Swift files
    /// - Parameters:
    ///   - paths: Directories (searched recursively) and `.swift` files
    ///   - exclude: Patterns for files and directories to skip (see `FileReader.findSwiftFiles(in:excluding:)`)
    /// - Returns: Array of all extracted code elements, in file path order
    /// - Throws: File system or parsing errors
    public func extractElements(fromPaths paths: [String], excluding exclude: [ExcludePattern] = []) throws -> [CodeElement] {
        try extractElements(fromFiles: FileReader.findSwiftFiles(in: paths, excluding: exclude))
    }

    /// Extracts the files in parallel (each file is parsed and walked independently) and returns
    /// their elements in file order. When files fail, the first failing file's error is thrown.
    private func extractElements(fromFiles swiftFiles: [String]) throws -> [CodeElement] {
        let results = swiftFiles.concurrentMap { filePath in
            Result { try self.extractElements(from: filePath) }
        }
        return try results.flatMap { try $0.get() }
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
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .function)
    }
    
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .initializer)
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .struct)
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .class)
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .enum)
    }
    
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .actor)
    }
    
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .protocol)
    }
    
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(node, as: .extension)
    }
    
    /// Records `node` if its type was requested; nested declarations are always visited.
    private func collect(_ node: some DeclSyntaxProtocol, as type: CodeElementType) -> SyntaxVisitorContinueKind {
        if configuration.elementTypes.contains(type), let element = createCodeElement(from: node, type: type) {
            extractedElements.append(element)
        }
        return .visitChildren
    }
    
    // Create code element from syntax node
    private func createCodeElement(from node: some DeclSyntaxProtocol, type: CodeElementType) -> CodeElement? {
        // Get name
        guard let name = extractName(from: node) else { return nil }

        if configuration.respectIgnoreDirectives && hasIgnoreDirective(node) {
            return nil
        }

        // The syntax that is compared: the whole declaration, or only its body
        let compared: Syntax
        if configuration.compareBodyOnly {
            guard let body = body(of: node) else { return nil }
            compared = body
        } else {
            compared = Syntax(node)
        }

        // Calculate actual line numbers
        let (startLine, endLine) = calculateLineNumbers(for: node)

        if endLine - startLine + 1 < configuration.minLines {
            return nil
        }
        if configuration.minTokens > 0 && !hasTokens(compared, atLeast: configuration.minTokens) {
            return nil
        }

        // Create signature (simplified - just the node description)
        let signature = node.description.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create code preview from actual source lines
        let codePreview = extractCodePreview(startLine: startLine, endLine: endLine)

        // Create tree node for similarity calculation
        let treeNode = ASTToTreeConverter.convertSyntaxNode(compared)
        
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
    
    /// Whether a comment directly before the declaration (in its leading trivia, which also covers
    /// comments above its attributes) contains `similarity-ignore`. Only this declaration is
    /// skipped; declarations nested in it are still extracted.
    private func hasIgnoreDirective(_ node: some DeclSyntaxProtocol) -> Bool {
        node.leadingTrivia.contains { piece in
            switch piece {
            case .lineComment(let text), .blockComment(let text),
                 .docLineComment(let text), .docBlockComment(let text):
                return text.contains(CodeElementExtractor.ignoreDirective)
            default:
                return false
            }
        }
    }

    /// Whether `node` has at least `minimum` tokens; stops counting once the minimum is reached.
    private func hasTokens(_ node: Syntax, atLeast minimum: Int) -> Bool {
        var count = 0
        for _ in node.tokens(viewMode: .sourceAccurate) {
            count += 1
            if count >= minimum { return true }
        }
        return false
    }

    /// The body compared with `compareBodyOnly`, or nil if the declaration has none.
    private func body(of node: some DeclSyntaxProtocol) -> Syntax? {
        let decl = Syntax(node)
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return funcDecl.body.map(Syntax.init)
        } else if let initDecl = decl.as(InitializerDeclSyntax.self) {
            return initDecl.body.map(Syntax.init)
        } else if let group = decl.asProtocol(DeclGroupSyntax.self) {
            return Syntax(group.memberBlock)
        }
        return nil
    }

    // Extract name from declaration
    private func extractName(from node: some DeclSyntaxProtocol) -> String? {
        let decl = Syntax(node)
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return funcDecl.name.text
        } else if let initDecl = decl.as(InitializerDeclSyntax.self) {
            // Name initializers like Swift does, e.g. `init(name:age:)` or `init?(_:)`.
            let labels = initDecl.signature.parameterClause.parameters.map { "\($0.firstName.text):" }.joined()
            return "init\(initDecl.optionalMark?.text ?? "")(\(labels))"
        } else if let structDecl = decl.as(StructDeclSyntax.self) {
            return structDecl.name.text
        } else if let classDecl = decl.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        } else if let enumDecl = decl.as(EnumDeclSyntax.self) {
            return enumDecl.name.text
        } else if let actorDecl = decl.as(ActorDeclSyntax.self) {
            return actorDecl.name.text
        } else if let protocolDecl = decl.as(ProtocolDeclSyntax.self) {
            return protocolDecl.name.text
        } else if let extensionDecl = decl.as(ExtensionDeclSyntax.self) {
            return extensionDecl.extendedType.trimmedDescription
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