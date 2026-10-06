import AppIntents
import WidgetKit
import AcaiAppModel

struct CodebaseStateProvider: AppIntentTimelineProvider {
    /// The app reloads timelines when it writes; this only bounds how long a missed reload lasts.
    static let refreshInterval: TimeInterval = 60 * 60

    var loadList: @Sendable () -> CodebaseWidgetSnapshotList = {
        CodebaseWidgetSnapshotStore(container: .standard)?.load() ?? CodebaseWidgetSnapshotList()
    }

    func placeholder(in context: Context) -> CodebaseStateEntry {
        CodebaseStateEntry(date: Date(), state: .analysed(.placeholder))
    }

    func snapshot(for configuration: SelectCodebaseIntent, in context: Context) async -> CodebaseStateEntry {
        let entry = entry(for: configuration)
        // The gallery previews what the widget does, even before the app has shared anything.
        return context.isPreview && entry.state == .nothingShared ? placeholder(in: context) : entry
    }

    func timeline(for configuration: SelectCodebaseIntent, in context: Context) async -> Timeline<CodebaseStateEntry> {
        makeTimeline(for: configuration)
    }

    /// `Context` has no initializer, so tests drive this half.
    func entry(for configuration: SelectCodebaseIntent) -> CodebaseStateEntry {
        let state = CodebaseWidgetPresentation(list: loadList()).state(codebaseID: configuration.codebase?.id)
        return CodebaseStateEntry(date: Date(), state: state)
    }

    func makeTimeline(for configuration: SelectCodebaseIntent) -> Timeline<CodebaseStateEntry> {
        let entry = entry(for: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(entry.date.addingTimeInterval(Self.refreshInterval)))
    }
}

extension CodebaseWidgetSnapshot {
    static var placeholder: CodebaseWidgetSnapshot {
        let analysedAt = Date().addingTimeInterval(-2 * 60 * 60)
        return CodebaseWidgetSnapshot(
            codebaseID: UUID(), codebaseName: "Açaí", analysedAt: analysedAt, freshnessCheckedAt: analysedAt,
            typeCount: 128, findingCount: 4, criticalFindingCount: 1)
    }
}
