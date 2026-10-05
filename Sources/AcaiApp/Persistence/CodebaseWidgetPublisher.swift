import Foundation
import WidgetKit
import AcaiRender

/// What the app knows about one codebase when it publishes. Deriving the widget's snapshot from it
/// walks a whole findings report, so the inputs are carried off the main actor and the derivation
/// happens there.
struct CodebaseWidgetInput: Sendable {
    /// Everything readable straight off the stored codebase and its freshness check.
    let snapshot: CodebaseWidgetSnapshot
    /// `nil` until the codebase's analysis has been computed, which is why the snapshot's counts
    /// are optional rather than zero.
    let analysis: CodebaseAnalysis?
}

/// Writes what the widget extension shows into the App Group container, then asks WidgetKit to
/// rebuild its timelines.
///
/// An actor because the app publishes from three places as it learns things, and two writes that
/// interleaved would let the later-read one lose the earlier's counts; serialising them means each
/// merge sees the previous write. Its work is off the main actor by construction.
actor CodebaseWidgetPublisher {
    static let shared = CodebaseWidgetPublisher()

    /// `nil` when the process holds no App Group entitlement, which is how a build without one
    /// presents itself; publishing then does nothing rather than failing.
    private let store: CodebaseWidgetSnapshotStore?
    private let reloadTimelines: @Sendable () -> Void

    init(
        store: CodebaseWidgetSnapshotStore? = CodebaseWidgetSnapshotStore(container: .standard),
        reloadTimelines: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.store = store
        self.reloadTimelines = reloadTimelines
    }

    /// `inputs` is one entry per codebase the app still has, so a deleted one stops being offered.
    /// Counts and freshness recorded against the same analysis survive an entry that doesn't carry
    /// them — see `CodebaseWidgetSnapshotList.merging(_:)`.
    ///
    /// A write failure is swallowed deliberately: a widget still showing its previous state is not
    /// worth an alert over an operation the user never asked for.
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
