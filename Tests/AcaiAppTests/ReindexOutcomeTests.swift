import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("Reindex outcome")
@MainActor
struct ReindexOutcomeTests {
    @Test func reindexingAMissingCodebaseThrowsInsteadOfSucceedingSilently() async {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ProjectBrowserViewModel(store: ProjectStore(baseDir: dir))

        await #expect(throws: ProjectCodebaseEditor.ReindexFailure.self) {
            try await model.editing.reindexOutcome(codebaseID: UUID())
        }
    }

    @Test func reindexingAReadableFolderCompletes() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "class Widget {}\n".write(
            to: source.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        let (model, codebaseID) = modelWithCodebase(at: source, baseDir: dir)

        #expect(await model.editing.reindex(codebaseID: codebaseID) == .completed)
        #expect(model.store.lastError == nil)
    }

    @Test func reindexingAnUnreachableFolderFailsWithARelocatableError() async {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, codebaseID) = modelWithCodebase(at: dir.appendingPathComponent("gone"), baseDir: dir)

        #expect(await model.editing.reindex(codebaseID: codebaseID) == .failed)
        #expect(model.store.lastError?.reason == .codebaseUnreachable)
        #expect(model.store.lastError?.relocatableCodebaseID == codebaseID)
    }

    @Test func managedCheckoutFailureIsNeverRelocatable() async {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, codebaseID) = modelWithCodebase(
            at: dir.appendingPathComponent("gone"), baseDir: dir, managedCheckout: ManagedCheckout())

        #expect(await model.editing.reindex(codebaseID: codebaseID) == .failed)
        #expect(model.store.lastError?.reason == .codebaseUnreachable)
        #expect(model.store.lastError?.relocatableCodebaseID == nil)
    }

    @Test func relocateCodebaseDropsArtifactAndReindexes() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "class Widget {}\n".write(
            to: source.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        let (model, codebaseID) = modelWithCodebase(at: dir.appendingPathComponent("gone"), baseDir: dir)
        model.store.artifacts[codebaseID] = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Old.swift"]),
            types: [TypeDeclaration(id: "Old", name: "Old", qualifiedName: "Old", kind: .class, accessLevel: .public)])
        model.editing.mutateCodebase(codebaseID) { $0.hasArtifact = true }

        let reindex = model.editing.relocateCodebase(
            id: codebaseID, directoryURL: source, securityScopedBookmark: nil)

        #expect(model.codebase(for: codebaseID)?.directoryPath == source.path)
        #expect(model.codebase(for: codebaseID)?.hasArtifact == false)
        #expect(model.store.artifacts[codebaseID] == nil)

        #expect(await reindex.value == .completed)
        #expect(model.codebase(for: codebaseID)?.hasArtifact == true)
        #expect(model.store.artifacts[codebaseID]?.types.map(\.name) == ["Widget"])
        #expect(model.store.lastError == nil)
    }

    @Test func pinningTheRevisionAlreadyAnalysedCompletesWithoutReindexing() async {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model, codebaseID) = modelWithCodebase(at: dir.appendingPathComponent("gone"), baseDir: dir)

        #expect(await model.editing.setAnalysedRevision(nil, codebaseID: codebaseID) == .completed)
        #expect(model.store.lastError == nil)
    }

    @Test func eachOutcomeMapsToTheStatusItShows() {
        #expect(AsyncOperationPhase(.completed, failure: "Failed") == .loaded)
        #expect(AsyncOperationPhase(.cancelled, failure: "Failed") == .idle)
        guard case .failed = AsyncOperationPhase(.failed, failure: "Failed") else {
            Issue.record("A failed operation must show its failure, not a completion")
            return
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-reindex-outcome-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func modelWithCodebase(
        at source: URL, baseDir: URL, managedCheckout: ManagedCheckout? = nil
    ) -> (ProjectBrowserViewModel, UUID) {
        let store = ProjectStore(baseDir: baseDir, analysisStore: AnalysisStore(
            directory: baseDir.appendingPathComponent("analysis-store")))
        let codebaseID = UUID()
        store.projects = [
            Project(
                title: "P", subtitle: "",
                codebases: [Codebase(
                    id: codebaseID, name: "C", directoryPath: source.path, managedCheckout: managedCheckout)])
        ]
        return (ProjectBrowserViewModel(store: store), codebaseID)
    }
}
