import AppIntents
import WidgetKit
import AcaiAppModel

struct CodebaseStateProvider: AppIntentTimelineProvider {
    /// How long before the entry is rebuilt. Nothing here changes on its own — the app reloads the
    /// timeline when it writes a new snapshot — but the relative "last analysed" age does, so the
    /// entry is refreshed on the hour rather than left to drift.
    static let refreshInterval: TimeInterval = 60 * 60

    /// Injected in tests; the real provider reads the App Group container.
    var loadList: @Sendable () -> CodebaseWidgetSnapshotList = {
        CodebaseWidgetSnapshotStore(container: .standard)?.load() ?? CodebaseWidgetSnapshotList()
    }

    func placeholder(in context: Context) -> CodebaseStateEntry {
        CodebaseStateEntry(date: Date(), state: .analysed(.placeholder))
    }

    func snapshot(for configuration: SelectCodebaseIntent, in context: Context) async -> CodebaseStateEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectCodebaseIntent, in context: Context) async -> Timeline<CodebaseStateEntry> {
        let entry = entry(for: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(entry.date.addingTimeInterval(Self.refreshInterval)))
    }

    private func entry(for configuration: SelectCodebaseIntent) -> CodebaseStateEntry {
        let state = CodebaseWidgetPresentation(list: loadList()).state(codebaseID: configuration.codebase?.id)
        return CodebaseStateEntry(date: Date(), state: state)
    }
}

extension CodebaseWidgetSnapshot {
    /// Stands in while the widget gallery renders a preview, before any real snapshot is readable.
    static let placeholder = CodebaseWidgetSnapshot(
        codebaseID: UUID(), codebaseName: "Açaí", analysedAt: Date(timeIntervalSince1970: 1_700_000_000),
        freshnessCheckedAt: Date(timeIntervalSince1970: 1_700_000_000), typeCount: 128, findingCount: 4,
        criticalFindingCount: 1)
}
