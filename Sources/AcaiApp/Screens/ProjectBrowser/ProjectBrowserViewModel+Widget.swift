import Foundation

extension ProjectBrowserViewModel {
    func publishWidgetSnapshots() {
        guard let publisher = store.widgetPublisher else { return }
        publisher.submit(widgetInputs())
    }

    /// Only what is cheap on the main actor; the publisher derives the counts off it.
    func widgetInputs() -> [CodebaseWidgetInput] {
        store.projects.flatMap { project in
            project.codebases.map {
                CodebaseWidgetInput(snapshot: widgetSnapshot(for: $0), analysis: currentAnalysis(for: $0.id))
            }
        }
    }

    private func widgetSnapshot(for codebase: Codebase) -> CodebaseWidgetSnapshot {
        var snapshot = CodebaseWidgetSnapshot(
            codebaseID: codebase.id,
            codebaseName: codebase.name,
            analysedAt: codebase.lastIndexed,
            analysedRevision: codebase.pinnedRevision,
            hasParseErrors: codebase.hasParseErrors)
        if let checked = freshnessCheck(for: codebase.id) {
            snapshot.isOutOfDate = checked.freshness == .stale
            snapshot.freshnessCheckedAt = checked.checkedAt
        }
        return snapshot
    }
}
