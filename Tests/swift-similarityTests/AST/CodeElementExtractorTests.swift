import Testing
@testable import swift_similarity

@Test("CodeElementExtractor configuration creation")
func testCodeElementExtractorConfiguration() {
    let defaultConfig = CodeElementExtractor.Configuration()
    #expect(defaultConfig.elementTypes.contains(.function))
    #expect(defaultConfig.elementTypes.contains(.struct))
    #expect(defaultConfig.elementTypes.contains(.class))
    #expect(defaultConfig.elementTypes.contains(.enum))
    #expect(defaultConfig.maxPreviewLines == 5)
    
    let customConfig = CodeElementExtractor.Configuration(
        elementTypes: [.function],
        maxPreviewLines: 3
    )
    #expect(customConfig.elementTypes == [.function])
    #expect(customConfig.maxPreviewLines == 3)
}

@Test("CodeElement creation")
func testCodeElementCreation() {
    let treeNode = SimpleTreeNode(label: "test")
    let element = CodeElement(
        elementType: .function,
        name: "testFunction",
        signature: "func testFunction() -> Void",
        filePath: "/test/path.swift",
        startLine: 1,
        endLine: 5,
        codePreview: "func testFunction() {\n    // test\n}",
        treeNode: treeNode
    )
    
    #expect(element.elementType == .function)
    #expect(element.name == "testFunction")
    #expect(element.signature == "func testFunction() -> Void")
    #expect(element.filePath == "/test/path.swift")
    #expect(element.startLine == 1)
    #expect(element.endLine == 5)
    #expect(element.codePreview.contains("testFunction"))
    #expect(element.treeNode.label == "test")
}

@Test("CodeElementType raw values")
func testCodeElementTypeRawValues() {
    #expect(CodeElementType.function.rawValue == "function")
    #expect(CodeElementType.struct.rawValue == "struct")
    #expect(CodeElementType.class.rawValue == "class")
    #expect(CodeElementType.enum.rawValue == "enum")
    
    #expect(CodeElementType(rawValue: "function") == .function)
    #expect(CodeElementType(rawValue: "struct") == .struct)
    #expect(CodeElementType(rawValue: "class") == .class)
    #expect(CodeElementType(rawValue: "enum") == .enum)
    #expect(CodeElementType(rawValue: "invalid") == nil)
}

@Test("CodeElementExtractor basic functionality")
func testCodeElementExtractorBasics() {
    let extractor = CodeElementExtractor()
    #expect(extractor.configuration.elementTypes.count == 4) // All types by default
    
    let configExtractor = CodeElementExtractor(
        configuration: CodeElementExtractor.Configuration(elementTypes: [.function])
    )
    #expect(configExtractor.configuration.elementTypes == [.function])
}