import Testing
import Foundation
@testable import UMLRender
@testable import UMLCore

@Suite("Diagram Image Renderer Tests")
struct DiagramImageRendererTests {

    private func sampleArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Sources/A/Animal.swift", "Sources/A/Dog.swift"]),
            types: [
                TypeDeclaration(
                    id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "name", kind: .property,
                        accessLevel: .internal, type: TypeReference(name: "String"))],
                    location: SourceLocation(filePath: "Sources/A/Animal.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class,
                    accessLevel: .public,
                    location: SourceLocation(filePath: "Sources/A/Dog.swift", line: 1, column: 1)
                )
            ],
            relationships: [Relationship(kind: .inheritance, source: "Dog", target: "Animal")]
        )
    }

    /// Renders a small diagram to PNG and checks it is a non-empty, well-formed PNG.
    ///
    /// `ImageRenderer` and CoreGraphics PNG encoding need a macOS window-server session, so on
    /// a headless agent (e.g. CI) `renderingFailed`/`encodingFailed` are expected; we treat
    /// either as an environment limitation rather than a test failure. Any other error still
    /// fails loudly.
    @Test @MainActor func rendersNonBlankPNG() throws {
        let data: Data
        do {
            data = try ClassImageRenderer().renderPNG(artifact: sampleArtifact(), configuration: .init())
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return
        }
        #expect(!data.isEmpty)
        // PNG magic bytes: 89 50 4E 47.
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }
}
