import Testing
import Foundation
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

// MARK: - Line Number Accuracy Test Suite

struct LineNumberAccuracyTests {
    // Shared test data setup
    static let swiftCode = """
import Foundation

struct TestStruct {
    let name: String
    let value: Int
}

func testFunction() -> String {
    return "test"
}

class TestClass {
    var property: String = "test"
    
    func method() {
        print("method called")
    }
}
"""
    
    // Helper method to create test elements
    static func createTestElements() throws -> [CodeElement] {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LineNumberTestFile.swift")
        
        try swiftCode.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let extractor = CodeElementExtractor()
        return try extractor.extractElements(from: tempURL.path)
    }
    
    @Test("Struct element line number validation")
    func testStructLineNumbers() throws {
        let elements = try Self.createTestElements()
        
        let structElement = elements.first { $0.elementType == CodeElementType.struct && $0.name == "TestStruct" }
        #expect(structElement != nil)
        
        if let structElement = structElement {
            #expect(structElement.startLine == 3)
            #expect(structElement.endLine == 6)
        }
    }
    
    @Test("Function element line number validation")
    func testFunctionLineNumbers() throws {
        let elements = try Self.createTestElements()
        
        let functionElement = elements.first { $0.elementType == CodeElementType.function && $0.name == "testFunction" }
        #expect(functionElement != nil)
        
        if let functionElement = functionElement {
            #expect(functionElement.startLine == 8)
            #expect(functionElement.endLine == 10)
        }
    }
    
    @Test("Class element line number validation")
    func testClassLineNumbers() throws {
        let elements = try Self.createTestElements()
        
        let classElement = elements.first { $0.elementType == CodeElementType.class && $0.name == "TestClass" }
        #expect(classElement != nil)
        
        if let classElement = classElement {
            #expect(classElement.startLine == 12)
            #expect(classElement.endLine == 18)
        }
    }
    
    @Test("Element logical order validation")
    func testElementOrder() throws {
        let elements = try Self.createTestElements()
        
        let structElement = elements.first { $0.elementType == CodeElementType.struct && $0.name == "TestStruct" }
        let functionElement = elements.first { $0.elementType == CodeElementType.function && $0.name == "testFunction" }
        let classElement = elements.first { $0.elementType == CodeElementType.class && $0.name == "TestClass" }
        
        #expect(structElement != nil)
        #expect(functionElement != nil)
        #expect(classElement != nil)
        
        if let structElement = structElement,
           let functionElement = functionElement,
           let classElement = classElement {
            #expect(structElement.startLine < functionElement.startLine) // struct comes before function
            #expect(functionElement.startLine < classElement.startLine) // function comes before class
        }
    }
    
    @Test("Element count validation")
    func testElementCount() throws {
        let elements = try Self.createTestElements()
        
        let structs = elements.filter { $0.elementType == CodeElementType.struct }
        let functions = elements.filter { $0.elementType == CodeElementType.function }
        let classes = elements.filter { $0.elementType == CodeElementType.class }
        
        #expect(structs.count >= 1) // At least TestStruct
        #expect(functions.count >= 1) // At least testFunction (possibly more from class methods)
        #expect(classes.count >= 1) // At least TestClass
    }
}

@Test("CodeElementExtractor code preview accuracy")
func testCodePreviewAccuracy() throws {
    let swiftCode = """
    struct SimpleStruct {
        let value: Int
    }
    """
    
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("SimpleTest.swift")
    
    try swiftCode.write(to: tempURL, atomically: true, encoding: .utf8)
    
    defer {
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    let extractor = CodeElementExtractor()
    let elements = try extractor.extractElements(from: tempURL.path)
    
    let structElement = elements.first { $0.elementType == CodeElementType.struct }
    #expect(structElement != nil)
    #expect(structElement?.codePreview.contains("struct SimpleStruct") == true)
    #expect(structElement?.codePreview.contains("let value: Int") == true)
}