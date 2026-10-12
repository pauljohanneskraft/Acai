import Testing
import Foundation
@testable import AcaiRender
@testable import AcaiCore

@Suite("Diagram Node Documentation")
struct DiagramNodeDocumentationTests {

    private func type(_ id: String, documentation: String? = nil) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: id, qualifiedName: id, kind: .class, accessLevel: .public,
            documentation: documentation)
    }

    private func node(_ type: TypeDeclaration) -> GeneratedDiagramNode {
        GeneratedDiagramNode(
            from: type, varianceKeywords: [:], modules: ModuleMap(roots: [], filePaths: []))
    }

    @Test func aNodeCarriesTheDocumentationItsTypeDeclared() {
        #expect(node(type("Repository", documentation: "Stores and retrieves orders.")).documentation
            == "Stores and retrieves orders.")
    }

    @Test func aNodeForAnUndocumentedTypeCarriesNothingToShow() {
        #expect(node(type("Bare")).documentation == nil)
    }
}
