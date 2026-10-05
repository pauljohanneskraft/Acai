import Foundation
import WidgetKit

/// Writes what the widget extension shows into the App Group container, then asks WidgetKit to
/// rebuild its timelines. Does file I/O — call off the main actor.
///
/// `store` is `nil` when the process holds no App Group entitlement, which is how a build without
/// one presents itself; publishing then does nothing rather than failing.
struct CodebaseWidgetPublisher: Sendable {
    let store: CodebaseWidgetSnapshotStore?
    var reloadTimelines: @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }

    init(store: CodebaseWidgetSnapshotStore? = CodebaseWidgetSnapshotStore(container: .standard)) {
        self.store = store
    }

    /// `snapshots` is one entry per codebase the app still has. Counts and freshness recorded
    /// against the same analysis survive an entry that doesn't carry them — see `merging(_:)`.
    ///
    /// A failure is swallowed deliberately: a widget that keeps showing its previous state is not
    /// worth an alert over an operation the user never asked for.
    func publish(_ snapshots: [CodebaseWidgetSnapshot]) {
        guard let store else { return }
        let current = store.load()
        let merged = current.merging(snapshots)
        // WidgetKit's reload budget is finite and most publishes change nothing.
        guard merged != current else { return }
        guard (try? store.save(merged)) != nil else { return }
        reloadTimelines()
    }
}
