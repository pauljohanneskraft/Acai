import SwiftUI

// The Repositories sidebar section — carved out of `ProjectBrowserView` to keep that file under
// the project's file-length limit, matching how `ProjectDetailView+AddDiagram.swift`/
// `ProjectDetailView+Delete.swift` already split that screen's own concerns into extensions.
extension ProjectBrowserView {
    /// A **Repositories** section below Projects, listing every shared `AcaiGit.GitRepository` that
    /// at least one codebase references (see `ProjectBrowserViewModel.repositoryIndex()`). Hidden
    /// entirely when the index is empty, rather than showing an always-there empty section — most
    /// users won't have any repository-backed codebases yet.
    @ViewBuilder
    var repositoriesSection: some View {
        let entries = model.repositoryIndex()
        if !entries.isEmpty {
            Section("Repositories") {
                ForEach(entries) { entry in
                    RepositoryRow(activityCenter: model.store.activityCenter, entry: entry)
                        .tag(ProjectBrowserViewModel.Selection.repository(entry.remoteURL))
                        .help(entry.remoteURL.absoluteString)
                        .accessibilityIdentifier("sidebar.repository.\(entry.remoteURL.absoluteString)")
                        .badge(entry.codebases.count)
                }
            }
        }
    }
}

/// Per-row in-flight state, applied to a repository row (the second legitimate site besides a
/// codebase row — `RepositoryDetailView`'s own "Fetch Now" registers into the same
/// `ActivityCenter` under `.repository(remoteURL)`). A spinner replaces the static icon while a
/// fetch is in flight, visible right where the user is looking in the sidebar, not just in the
/// global Activity indicator.
private struct RepositoryRow: View {
    @ObservedObject var activityCenter: ActivityCenter
    let entry: RepositoryIndexEntry

    private var isBusy: Bool { activityCenter.isBusy(.repository(entry.remoteURL)) }

    var body: some View {
        Label {
            Text(entry.remoteURL.lastPathComponent)
        } icon: {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Fetching")
            } else {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
            }
        }
    }
}
