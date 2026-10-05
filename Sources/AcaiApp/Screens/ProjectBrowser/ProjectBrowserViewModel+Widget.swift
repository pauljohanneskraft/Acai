import Foundation
import AcaiRender

extension ProjectBrowserViewModel {
    /// Shares every codebase's state with the widget extension, which cannot read a codebase's
    /// folder itself. Gathers on the main actor — the stores it reads are main-actor state — and
    /// writes off it.
    func publishWidgetSnapshots() {
        let snapshots = store.projects.flatMap { project in
            project.codebases.map { widgetSnapshot(for: $0) }
        }
        let publisher = CodebaseWidgetPublisher()
        Task.detached(priority: .utility) {
            publisher.publish(snapshots)
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
        if let analysis = analysis(for: codebase.id) {
            snapshot.typeCount = analysis.metrics.counts.totalTypes
            let findings = AtlasFindings(
                quality: analysis.quality, deadCode: analysis.deadCode, health: analysis.health
            ).findings
            snapshot.findingCount = findings.count
            snapshot.criticalFindingCount = findings.count(where: { $0.severity == .critical })
        }
        return snapshot
    }
}
