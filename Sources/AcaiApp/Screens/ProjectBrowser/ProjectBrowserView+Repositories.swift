import SwiftUI

// B05's Repositories sidebar section — carved out of `ProjectBrowserView` to keep that file under
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
                    Label(entry.remoteURL.lastPathComponent, systemImage: repositoryIconName)
                        .tag(ProjectBrowserViewModel.Selection.repository(entry.remoteURL))
                        .help(entry.remoteURL.absoluteString)
                        .accessibilityIdentifier("sidebar.repository.\(entry.remoteURL.absoluteString)")
                        .badge(entry.codebases.count)
                }
            }
        }
    }

    private var repositoryIconName: String { "point.3.filled.connected.trianglepath.dotted" }
}
