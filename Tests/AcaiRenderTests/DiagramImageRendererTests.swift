import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import AcaiRender
@testable import AcaiCore

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

    /// `ImageRenderer` and CoreGraphics PNG encoding need a macOS window-server session, so on
    /// a headless agent (e.g. CI) `renderingFailed`/`encodingFailed` are expected and treated as
    /// an environment limitation rather than a test failure. Any other error still fails loudly.
    @Test @MainActor func rendersNonBlankPNG() throws {
        let data: Data
        do {
            data = try ClassImageRenderer().renderPNG(artifact: sampleArtifact(), configuration: .init())
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return
        }
        #expect(!data.isEmpty)
        // PNG magic bytes.
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    /// The engine hands the rendered `CGImage` to its encoder and returns exactly those bytes, so
    /// nothing re-wraps or re-rasterises it on the way out — the intermediate copy #484 removes.
    @Test @MainActor func routesTheRenderedImageThroughItsEncoderUntouched() throws {
        let encoder = RecordingImageEncoder()
        let data: Data
        do {
            data = try DiagramImageRenderer(encoder: encoder).render(
                Color.blue.frame(width: 120, height: 80),
                contentSize: CGSize(width: 120, height: 80), scale: 1)
        } catch DiagramImageRenderError.renderingFailed {
            return
        }

        #expect(data == RecordingImageEncoder.sentinel)
        #expect(encoder.encoded.count == 1)
    }
}

/// Records what the engine hands its encoder, answering with bytes no real encoder would produce
/// so a test can tell a pass-through from a re-encode.
private final class RecordingImageEncoder: DiagramImageEncoding, @unchecked Sendable {
    static let sentinel = Data([0xDE, 0xAD, 0xBE, 0xEF])

    private let lock = NSLock()
    private var images: [CGImage] = []

    var encoded: [CGImage] { lock.withLock { images } }

    func encode(_ image: CGImage) throws -> Data {
        lock.withLock { images.append(image) }
        return Self.sentinel
    }
}
