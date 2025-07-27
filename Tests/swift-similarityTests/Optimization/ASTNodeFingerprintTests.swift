import Testing
import Foundation
@testable import swift_similarity

// MARK: - AST Node Fingerprint Tests

struct ASTNodeFingerprintTests {
    
    @Test("Fingerprint creation from simple tree")
    func testFingerprintCreation() throws {
        // Create a simple tree node
        let rootNode = SimpleTreeNode(label: "FunctionDecl", children: [
            SimpleTreeNode(label: "Identifier", children: []),
            SimpleTreeNode(label: "Block", children: [
                SimpleTreeNode(label: "ReturnStmt", children: [])
            ])
        ])
        
        let fingerprint = rootNode.extractFingerprint()
        
        #expect(fingerprint.totalNodes == 4)
        #expect(fingerprint.maxDepth == 2)
        #expect(fingerprint.leafNodeCount == 2) // Identifier, ReturnStmt
        #expect(fingerprint.uniqueNodeTypes == 4)
        #expect(fingerprint.nodeTypeCounts["FunctionDecl"] == 1)
        #expect(fingerprint.nodeTypeCounts["Identifier"] == 1)
        #expect(fingerprint.nodeTypeCounts["Block"] == 1)
        #expect(fingerprint.nodeTypeCounts["ReturnStmt"] == 1)
    }
    
    @Test("Distance calculation between identical trees")
    func testDistanceCalculation() throws {
        let tree1 = SimpleTreeNode(label: "FunctionDecl", children: [
            SimpleTreeNode(label: "Identifier", children: [])
        ])
        
        let tree2 = SimpleTreeNode(label: "FunctionDecl", children: [
            SimpleTreeNode(label: "Identifier", children: [])
        ])
        
        let fingerprint1 = tree1.extractFingerprint()
        let fingerprint2 = tree2.extractFingerprint()
        
        let distance = fingerprint1.distance(to: fingerprint2)
        let similarity = fingerprint1.similarity(to: fingerprint2)
        
        #expect(distance == 0.0)
        #expect(similarity == 1.0)
    }
    
    @Test("Hash values generation")
    func testHashValuesGeneration() throws {
        let rootNode = SimpleTreeNode(label: "FunctionDecl", children: [
            SimpleTreeNode(label: "Identifier", children: [])
        ])
        
        let fingerprint = rootNode.extractFingerprint()
        let hashCount = 3
        let hashValues = fingerprint.hashValues(hashCount: hashCount)
        
        #expect(hashValues.count == hashCount)
        
        // Hash values should be deterministic
        let hashValues2 = fingerprint.hashValues(hashCount: hashCount)
        #expect(hashValues == hashValues2)
    }
    
    @Test("Similarity check between different trees")
    func testMightBeSimilarCheck() throws {
        // Similar sized trees
        let tree1 = SimpleTreeNode(label: "FunctionDecl", children: [
            SimpleTreeNode(label: "Identifier", children: [])
        ])
        
        let tree2 = SimpleTreeNode(label: "FunctionDecl", children: [
            SimpleTreeNode(label: "Block", children: [])
        ])
        
        let fingerprint1 = tree1.extractFingerprint()
        let fingerprint2 = tree2.extractFingerprint()
        
        #expect(fingerprint1.mightBeSimilar(to: fingerprint2) == true)
        
        // Very different sized trees
        let largeTree = SimpleTreeNode(label: "ClassDecl", children: [
            SimpleTreeNode(label: "PropertyDecl", children: []),
            SimpleTreeNode(label: "PropertyDecl", children: []),
            SimpleTreeNode(label: "MethodDecl", children: [
                SimpleTreeNode(label: "Block", children: [
                    SimpleTreeNode(label: "Statement", children: [])
                ])
            ])
        ])
        
        let smallTree = SimpleTreeNode(label: "VarDecl", children: [])
        
        let largeFp = largeTree.extractFingerprint()
        let smallFp = smallTree.extractFingerprint()
        
        #expect(largeFp.mightBeSimilar(to: smallFp) == false)
    }
}