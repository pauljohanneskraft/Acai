import Foundation

extension ProjectBrowserViewModel {
    /// Shares every codebase's state with the widget extension, which cannot read a codebase's
    /// folder itself. Gathers only what is cheap to read on the main actor; the snapshot's counts
    /// are derived from the analysis inside the publisher, off it.
    func publishWidgetSnapshots() {
        let inputs = store.projects.flatMap { project in
            project.codebases.map {
                CodebaseWidgetInput(snapshot: widgetSnapshot(for: $0), analysis: analysis(for: $0.id))
            }
        }
        Task { await CodebaseWidgetPublisher.shared.publish(inputs) }
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
