import Testing
@testable import swift_similarity

@Test("AST parsing from source code")
func testASTParsingFromSource() {
    let source = """
        func hello() {
            print("Hello, World!")
        }
        """
    
    let ast = SwiftASTParser.parseSource(source)
    #expect(ast.statements.count > 0)
} 