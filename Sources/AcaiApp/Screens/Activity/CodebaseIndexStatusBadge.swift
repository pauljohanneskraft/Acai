import SwiftUI

/// Per-row in-flight state: a spinner in place of the "last indexed" checkmark on a codebase
/// row while a reindex/fetch/clone concerning it is in flight — visible exactly where the user is
/// looking, not just in the global Activity indicator (`ActivityIndicatorView`). Takes
/// `ActivityCenter` as an `@ObservedObject` directly (not read once through a parent's plain method
/// call) so this badge live-updates as operations start/finish, independent of whatever else does
/// or doesn't trigger a re-render of the row around it.
struct CodebaseIndexStatusBadge: View {
    @ObservedObject var activityCenter: ActivityCenter
    let codebase: Codebase

    /// Labelled by its own title, so an Atlas export or GitHub pull isn't mislabeled "Indexing".
    private var busyOperation: ActivityOperation? { activityCenter.operation(for: .codebase(codebase.id)) }

    var body: some View {
        Group {
            if let busyOperation {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(busyOperation.title)
                    .help(busyOperation.title)
                    .accessibilityIdentifier("codebaseRow.indexingSpinner.\(codebase.id)")
            } else if codebase.hasArtifact {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .accessibilityLabel("Indexed")
                    .help("Indexed")
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityLabel("Not yet indexed")
                    .help("Not yet indexed")
            }
        }
    }
}
