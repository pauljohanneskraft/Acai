import Foundation
import Testing
@testable import AcaiApp

@Suite("Reindex outcome")
@MainActor
struct ReindexOutcomeTests {
    @Test func reindexingAMissingCodebaseThrowsInsteadOfSucceedingSilently() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-reindex-outcome-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ProjectBrowserViewModel(store: ProjectStore(baseDir: dir))

        await #expect(throws: ProjectCodebaseEditor.ReindexFailure.self) {
            try await model.editing.reindexOutcome(codebaseID: UUID())
        }
    }
}
