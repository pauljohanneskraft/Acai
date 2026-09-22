import Foundation
import Testing
import AcaiCore
@testable import AcaiCLI

@Suite("CLI: ArtifactSource")
struct ArtifactSourceTests {

    /// A stored analysis that can no longer be decoded (schema drift, e.g. the required
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

    /// An artifact whose `schemaVersion` is newer than this build understands names both the found
    /// and expected versions, rather than being misread or failing some unrelated way downstream.
    @Test func artifactFromANewerSchemaVersionNamesBothVersions() throws {
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift))
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(artifact)) as? [String: Any]
        )
        json["schemaVersion"] = 999
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("future-schema-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var thrown: Error?
        do {
            _ = try ArtifactSource.loadStored(url.path)
        } catch {
            thrown = error
        }
        let message = String(describing: try #require(thrown))
        #expect(message.contains("999"))
        #expect(message.contains("\(CodeArtifact.currentSchemaVersion)"))
    }
}
