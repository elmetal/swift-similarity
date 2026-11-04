import Testing
@testable import swift_similarity

@Test("AST to Tree conversion")
func testASTToTreeConversion() {
    let source = """
        func hello() {
            print("Hello")
        }
        """
    
    let ast = SwiftASTParser.parseSource(source)
    let tree = ASTToTreeConverter.convert(ast)
    
    #expect(tree.label == "SourceFile")
    #expect(!tree.children.isEmpty)
}

@Test("Simple source code conversion")
func testSimpleSourceConversion() {
    let source = "let x = 42"
    
    let ast = SwiftASTParser.parseSource(source)
    let tree = ASTToTreeConverter.convert(ast)
    
    #expect(tree.label == "SourceFile")
    #expect(!tree.children.isEmpty)
} 
private func allLabels(_ tree: TreeNode) -> [String] {
    [tree.label] + tree.children.flatMap { allLabels($0) }
}

@Test("Nested nodes get their concrete node type label")
func testNestedNodeLabels() {
    let source = """
        func check(value: Int) -> Bool {
            if value > 0 {
                return true
            }
            return false
        }
        """
    
    let tree = ASTToTreeConverter.convert(SwiftASTParser.parseSource(source))
    let labels = allLabels(tree)
    
    #expect(labels.contains("FunctionDecl"))
    #expect(labels.contains("IfExpr"))
    #expect(labels.contains("ReturnStmt"))
    #expect(labels.contains("func"))
    #expect(labels.contains("Identifier"))
    #expect(labels.contains("IntegerLiteral"))
    #expect(!labels.contains("Syntax"))
    #expect(!labels.contains("Token"))
}

@Test("Renamed identifiers produce identical trees by default")
func testRenamedIdentifiersAreIdentical() {
    let source1 = "func sum(a: Int, b: Int) -> Int { let total = a + b; return total }"
    let source2 = "func add(x: Int, y: Int) -> Int { let result = x + y; return result }"
    
    let tree1 = ASTToTreeConverter.convert(SwiftASTParser.parseSource(source1))
    let tree2 = ASTToTreeConverter.convert(SwiftASTParser.parseSource(source2))
    
    #expect(APTED().editDistance(between: tree1, and: tree2) == 0.0)
}

@Test("Identifier names can be included in labels")
func testIncludeIdentifierNames() {
    let source = "let count = 1"
    let options = ASTToTreeConverter.Options(includeIdentifierNames: true, includeLiteralValues: true)
    let tree = ASTToTreeConverter.convert(SwiftASTParser.parseSource(source), options: options)
    let labels = allLabels(tree)
    
    #expect(labels.contains("Identifier(count)"))
    #expect(labels.contains("IntegerLiteral(1)"))
}

@Test("Structural changes produce a non-zero distance")
func testStructuralChangeDetected() {
    let source1 = "func f(a: Int) -> Int { return a + 1 }"
    let source2 = "func f(a: Int) -> Int { if a > 0 { return a } ; return 1 }"
    
    let tree1 = ASTToTreeConverter.convert(SwiftASTParser.parseSource(source1))
    let tree2 = ASTToTreeConverter.convert(SwiftASTParser.parseSource(source2))
    
    #expect(APTED().editDistance(between: tree1, and: tree2) > 0.0)
}
