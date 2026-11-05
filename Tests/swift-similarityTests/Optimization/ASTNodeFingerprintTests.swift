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
}
