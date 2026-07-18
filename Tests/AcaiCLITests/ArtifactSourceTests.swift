import Foundation
import Testing
@testable import AcaiCLI

@Suite("CLI: ArtifactSource")
struct ArtifactSourceTests {

    /// A stored analysis that can no longer be decoded (schema drift, e.g. the now-required
    /// `accessLevel`) is reported as "regenerate it" — the CLI equivalent of treating the codebase
    /// as not indexed — rather than surfacing a raw `DecodingError`.
    @Test func staleStoredAnalysisGivesRegenerateMessage() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var thrown: Error?
        do {
            _ = try ArtifactSource.loadStored(url.path)
        } catch {
            thrown = error
        }
        let message = String(describing: try #require(thrown))
        #expect(message.contains("older Açaí version"))
        #expect(message.contains("Re-run"))
    }
}
