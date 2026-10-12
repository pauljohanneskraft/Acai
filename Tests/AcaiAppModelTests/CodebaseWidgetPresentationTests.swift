import Foundation
import Testing
@testable import AcaiAppModel

@Suite("CodebaseWidgetPresentation")
struct CodebaseWidgetPresentationTests {
    private let first = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let second = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let analysed = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(_ id: UUID, _ name: String, analysedAt: Date? = nil) -> CodebaseWidgetSnapshot {
        CodebaseWidgetSnapshot(codebaseID: id, codebaseName: name, analysedAt: analysedAt)
    }

    @Test("With nothing shared, the widget says so rather than naming a codebase")
    func nothingShared() {
        let presentation = CodebaseWidgetPresentation(list: CodebaseWidgetSnapshotList())
        #expect(presentation.state(codebaseID: nil) == .nothingShared)
        #expect(presentation.state(codebaseID: first) == .nothingShared)
    }

    @Test("A configured codebase that no longer exists is reported as missing, not as empty")
    func missingCodebase() {
        let presentation = CodebaseWidgetPresentation(
            list: CodebaseWidgetSnapshotList(snapshots: [snapshot(first, "Acai", analysedAt: analysed)]))
        #expect(presentation.state(codebaseID: second) == .codebaseMissing)
    }

    @Test("A codebase that has never been analysed is distinguished from an analysed one")
    func neverAnalysed() {
        let presentation = CodebaseWidgetPresentation(
            list: CodebaseWidgetSnapshotList(snapshots: [snapshot(first, "Acai")]))
        #expect(presentation.state(codebaseID: first) == .notAnalysed(snapshot(first, "Acai")))
    }

    @Test("The configured codebase is shown even when another was analysed more recently")
    func configuredCodebaseWins() {
        let presentation = CodebaseWidgetPresentation(list: CodebaseWidgetSnapshotList(snapshots: [
            snapshot(first, "Acai", analysedAt: analysed),
            snapshot(second, "Other", analysedAt: analysed.addingTimeInterval(60))
        ]))
        #expect(presentation.state(codebaseID: first).snapshot?.codebaseID == first)
    }

    @Test("An unconfigured widget shows the most recently analysed codebase")
    func unconfiguredShowsMostRecent() {
        let presentation = CodebaseWidgetPresentation(list: CodebaseWidgetSnapshotList(snapshots: [
            snapshot(first, "Acai", analysedAt: analysed),
            snapshot(second, "Other", analysedAt: analysed.addingTimeInterval(60))
        ]))
        #expect(presentation.state(codebaseID: nil).snapshot?.codebaseID == second)
    }

    @Test("An unconfigured widget whose codebases are all unanalysed still shows one")
    func unconfiguredWithNoAnalysisStillShowsOne() {
        let presentation = CodebaseWidgetPresentation(list: CodebaseWidgetSnapshotList(snapshots: [
            snapshot(second, "Other"),
            snapshot(first, "Acai")
        ]))
        #expect(presentation.state(codebaseID: nil) == .notAnalysed(snapshot(first, "Acai")))
    }

    @Test("Two codebases analysed in the same instant resolve by name, not arbitrarily")
    func tiesBreakOnName() {
        let presentation = CodebaseWidgetPresentation(list: CodebaseWidgetSnapshotList(snapshots: [
            snapshot(second, "Other", analysedAt: analysed),
            snapshot(first, "Acai", analysedAt: analysed)
        ]))
        #expect(presentation.state(codebaseID: nil).snapshot?.codebaseName == "Acai")
    }
}
