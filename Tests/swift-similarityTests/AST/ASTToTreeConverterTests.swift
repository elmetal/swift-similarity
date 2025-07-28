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