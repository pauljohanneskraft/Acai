import Foundation
import WidgetKit
import AcaiRender

/// One codebase as the app knows it when publishing; `analysis` is `nil` until computed, never zero counts.
struct CodebaseWidgetInput: Sendable {
    let snapshot: CodebaseWidgetSnapshot
    let analysis: CodebaseAnalysis?
}

/// Writes the widget's snapshots into the App Group container; an actor so each merge sees the previous write.
actor CodebaseWidgetPublisher {
    private let store: CodebaseWidgetSnapshotStore?
    private let reloadTimelines: @Sendable () -> Void
    private let submissions: AsyncStream<[CodebaseWidgetInput]>.Continuation

    init(
        store: CodebaseWidgetSnapshotStore? = CodebaseWidgetSnapshotStore(container: .standard),
        reloadTimelines: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.store = store
        self.reloadTimelines = reloadTimelines
        // Newest-only, in submission order: a burst coalesces and an older state never lands after a newer one.
        let (stream, submissions) = AsyncStream.makeStream(
            of: [CodebaseWidgetInput].self, bufferingPolicy: .bufferingNewest(1))
        self.submissions = submissions
        Task.detached(priority: .utility) { [weak self] in
            for await inputs in stream {
                await self?.publish(inputs)
            }
        }
    }

    deinit {
        submissions.finish()
    }

    nonisolated func submit(_ inputs: [CodebaseWidgetInput]) {
        submissions.yield(inputs)
    }

    /// A failed write is dropped: the widget keeps its previous state rather than alerting over background work.
    func publish(_ inputs: [CodebaseWidgetInput]) {
        guard let store else { return }
        let current = store.load()
        let merged = current.merging(inputs.map(snapshot(from:)))
        // WidgetKit's reload budget is finite and most publishes change nothing.
        guard merged != current else { return }
        guard (try? store.save(merged)) != nil else { return }
        reloadTimelines()
    }

    private func snapshot(from input: CodebaseWidgetInput) -> CodebaseWidgetSnapshot {
        guard let analysis = input.analysis else { return input.snapshot }
        var snapshot = input.snapshot
        snapshot.typeCount = analysis.metrics.counts.totalTypes
        let findings = AtlasFindings(
            quality: analysis.quality, deadCode: analysis.deadCode, health: analysis.health
        ).findings
        snapshot.findingCount = findings.count
        snapshot.criticalFindingCount = findings.count(where: { $0.severity == .critical })
        return snapshot
    }
}
