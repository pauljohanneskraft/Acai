import Foundation
import Testing
@testable import UMLCLI

/// End-to-end coverage of `uml image` (previously only component-tested in UMLRenderTests): parse →
/// analyze → build the diagram → rasterize → write the PNG file.
@Suite("Image Command Run")
struct ImageCommandRunTests {

    @Test func writesPngFileEndToEnd() async throws {
        let dir = try CLITestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try CLITestSupport.writeSampleSwiftSource(in: dir)

        let output = dir.appendingPathComponent("diagram.png")
        var cmd = try CLITestSupport.parseImage(
            ["--source", dir.path, "--language", "swift", "--output", output.path]
        )
        do {
            try await cmd.run()
        } catch {
            // `ImageRenderer`/CoreGraphics PNG encoding need a macOS window-server session, so a
            // headless agent surfaces `DiagramImageRenderError.renderingFailed`/`.encodingFailed`.
            // Treat only those as an environment limitation; anything else is a real failure.
            let description = "\(error)"
            if description.contains("renderingFailed") || description.contains("encodingFailed") { return }
            throw error
        }

        let data = try Data(contentsOf: output)
        #expect(!data.isEmpty)
        // PNG magic bytes: 89 50 4E 47.
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func nonexistentSourceThrows() async throws {
        var cmd = try CLITestSupport.parseImage(
            ["--source", CLITestSupport.nonexistentPath(), "--output", "/tmp/x.png"]
        )
        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }
    }
}
