import Foundation
import Testing
import WidgetKit
@testable import AcaiWidget
@testable import AcaiAppModel

@Suite("CodebaseStateProvider")
struct CodebaseStateProviderTests {
    private let codebaseID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private func provider(_ snapshots: [CodebaseWidgetSnapshot]) -> CodebaseStateProvider {
        var provider = CodebaseStateProvider()
        provider.loadList = { CodebaseWidgetSnapshotList(snapshots: snapshots) }
        return provider
    }

    private var analysedSnapshot: CodebaseWidgetSnapshot {
        CodebaseWidgetSnapshot(
            codebaseID: codebaseID, codebaseName: "Acai", analysedAt: Date(timeIntervalSince1970: 1_700_000_000),
            freshnessCheckedAt: Date(timeIntervalSince1970: 1_700_000_100), typeCount: 12, findingCount: 3)
    }

    @Test("The timeline carries the configured codebase's state, and one entry refreshed on the hour")
    func timelineCarriesConfiguredState() {
        let entity = CodebaseWidgetEntity(id: codebaseID, name: "Acai")
        let timeline = provider([analysedSnapshot]).makeTimeline(for: SelectCodebaseIntent(codebase: entity))

        #expect(timeline.entries.count == 1)
        #expect(timeline.entries.first?.state == .analysed(analysedSnapshot))
        #expect(CodebaseStateProvider.refreshInterval == 60 * 60)
    }

    @Test("An unconfigured widget still has a state to show")
    func unconfiguredWidgetHasState() {
        let entry = provider([analysedSnapshot]).entry(for: SelectCodebaseIntent())
        #expect(entry.state.snapshot?.codebaseID == codebaseID)
    }

    @Test("With nothing shared, the entry says so rather than naming a codebase")
    func nothingSharedEntry() {
        #expect(provider([]).entry(for: SelectCodebaseIntent()).state == .nothingShared)
    }

    @Test("The entry's deep link opens the codebase shown, not the app's front door")
    func entryDeepLinksToItsCodebase() {
        let entry = provider([analysedSnapshot]).entry(for: SelectCodebaseIntent())
        #expect(entry.state.snapshot?.address.url.absoluteString == "acai://codebase/\(codebaseID.uuidString)")
    }

    @Test("The gallery placeholder stands in for a real analysis rather than an empty state")
    func placeholderLooksAnalysed() {
        #expect(CodebaseWidgetSnapshot.placeholder.analysedAt != nil)
        #expect(CodebaseWidgetSnapshot.placeholder.findingCount != nil)
    }
}

@Suite("CodebaseWidgetEntityQuery")
struct CodebaseWidgetEntityQueryTests {
    private let first = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let second = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func query() -> CodebaseWidgetEntityQuery {
        var query = CodebaseWidgetEntityQuery()
        query.snapshots = { [
            CodebaseWidgetSnapshot(codebaseID: self.second, codebaseName: "Zebra"),
            CodebaseWidgetSnapshot(codebaseID: self.first, codebaseName: "Acai")
        ] }
        return query
    }

    @Test("Suggestions are sorted by name, so the picker's order doesn't depend on the file's")
    func suggestionsAreSortedByName() async throws {
        #expect(try await query().suggestedEntities().map(\.name) == ["Acai", "Zebra"])
    }

    @Test("A stored configuration resolves back to its codebase")
    func identifiersResolve() async throws {
        #expect(try await query().entities(for: [first]).map(\.name) == ["Acai"])
    }

    @Test("Searching matches part of a name, case- and diacritic-insensitively")
    func searchMatchesPartOfAName() async throws {
        #expect(try await query().entities(matching: "zeb").map(\.name) == ["Zebra"])
    }
}
