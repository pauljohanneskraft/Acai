import SwiftUI

struct CodebaseIndexStatusBadge: View {
    @ObservedObject var activityCenter: ActivityCenter
    let codebase: Codebase

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
                    .accessibilityLabel(.app("View.CodebaseIndexStatusBadge.Indexed"))
                    .help(.app("View.CodebaseIndexStatusBadge.Indexed"))
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityLabel(.app("View.CodebaseIndexStatusBadge.NotYetIndexed"))
                    .help(.app("View.CodebaseIndexStatusBadge.NotYetIndexed"))
            }
        }
    }
}
