import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Regression test for a real ordering bug: `reindex` used to mark itself "done" in `ActivityCenter`
/// before `ProjectStore.saveArtifact`'s fire-and-forget disk write had even started, so a caller
/// keying an "is this settled" signal off `ActivityCenter` could observe "done" before the artifact
/// actually landed on disk.
@Suite("reindex artifact persistence")
@MainActor
struct ReindexArtifactPersistenceTests {
    @Test("The artifact is on disk the instant reindex() returns, not just eventually")
    func artifactIsOnDiskImmediatelyAfterReindexReturns() async throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = baseDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        try "class Widget {}\n".write(
            to: sourceDir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)

        // A store shared across both `ProjectStore` instances below, the same way the real
        // `~/.acai/analysis` is shared across app launches — under `baseDir` so it's cleaned up by
        // this test's own `defer`, never the real store.
        let analysisStore = AnalysisStore(directory: baseDir.appendingPathComponent("analysis-store"))
        let store = ProjectStore(baseDir: baseDir, analysisStore: analysisStore)
        let codebaseID = UUID()
        store.projects = [
            Project(
                title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: sourceDir.path)]
            )
        ]
        let model = ProjectBrowserViewModel(store: store)

        await model.editing.reindex(codebaseID: codebaseID)

        let freshStore = ProjectStore(baseDir: baseDir, analysisStore: analysisStore)
        freshStore.projects = store.projects
        freshStore.loadArtifact(for: codebaseID)
        let artifact = try #require(freshStore.artifacts[codebaseID])
        #expect(artifact.types.contains { $0.name == "Widget" })
    }
}
