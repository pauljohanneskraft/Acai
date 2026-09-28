#if os(macOS)
import Foundation
import Testing
@testable import AcaiCLI

/// macOS-only: the `atlas` subcommand embeds rendered diagrams and is not compiled on Linux.
///
/// Unlike `image`, a renderer that cannot run headlessly does not fail the command — each diagram
/// that fails becomes a page saying so — so these assertions hold with or without a window-server
/// session.
@Suite("Atlas Command Run")
struct AtlasCommandRunTests {

    @Test func writesPdfFileEndToEnd() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("atlas.pdf")
            var cmd = try CLITestSupport.parseAtlas(
                ["--source", dir.path, "--language", "swift", "--output", output.path]
            )
            try await cmd.run()

            let data = try Data(contentsOf: output)
            #expect(!data.isEmpty)
            // PDF magic bytes: %PDF.
            #expect(Array(data.prefix(4)) == [0x25, 0x50, 0x44, 0x46])
        }
    }

    @Test func nonexistentSourceThrows() async throws {
        var cmd = try CLITestSupport.parseAtlas(
            ["--source", CLITestSupport.nonexistentPath(), "--output", "/tmp/atlas.pdf"]
        )
        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }
    }

    @Test func aMissingRulesFileIsRejected() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            var cmd = try CLITestSupport.parseAtlas([
                "--source", dir.path, "--language", "swift",
                "--output", dir.appendingPathComponent("atlas.pdf").path,
                "--rules", CLITestSupport.nonexistentPath()
            ])
            await #expect(throws: (any Error).self) {
                try await cmd.run()
            }
        }
    }

    @Test func anOutOfRangeNodeLimitFailsValidation() {
        #expect(throws: (any Error).self) {
            _ = try CLITestSupport.parseAtlas(
                ["--source", "/tmp", "--output", "/tmp/atlas.pdf", "--max-nodes", "0"])
        }
    }

    @Test func aNonPositiveScaleFailsValidation() {
        #expect(throws: (any Error).self) {
            _ = try CLITestSupport.parseAtlas(
                ["--source", "/tmp", "--output", "/tmp/atlas.pdf", "--scale", "0"])
        }
    }
}
#endif
