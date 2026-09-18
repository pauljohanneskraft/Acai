import SwiftUI

extension ProjectBrowserView {
    /// Hidden entirely when the index is empty, rather than showing an always-there empty section —
    /// most users won't have any repository-backed codebases yet.
    @ViewBuilder
    var repositoriesSection: some View {
        let entries = model.repositoryIndex()
        if !entries.isEmpty {
            Section(.app("View.ProjectBrowserView.Repositories")) {
                ForEach(entries) { entry in
                    // `.badge` before `.tag`: after it, the row stops taking selection clicks.
                    RepositoryRow(activityCenter: model.store.activityCenter, entry: entry)
                        .badge(entry.codebases.count)
                        .tag(ProjectBrowserViewModel.Selection.repository(entry.remoteURL))
                        .help(entry.remoteURL.absoluteString)
                        .accessibilityIdentifier("sidebar.repository.\(entry.remoteURL.absoluteString)")
                }
            }
        }
    }
}

/// `RepositoryDetailView`'s "Fetch Now" registers into the same `ActivityCenter` under
/// `.repository(remoteURL)`, so a spinner replaces the static icon here too while a fetch is in
/// flight.
private struct RepositoryRow: View {
    @ObservedObject var activityCenter: ActivityCenter
    let entry: RepositoryIndexEntry

    private var isBusy: Bool { activityCenter.isBusy(.repository(entry.remoteURL)) }

    var body: some View {
        Label {
            Text(verbatim: entry.remoteURL.lastPathComponent)
        } icon: {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(.app("View.RepositoryRow.Fetching"))
            } else {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
            }
        }
    }
}
