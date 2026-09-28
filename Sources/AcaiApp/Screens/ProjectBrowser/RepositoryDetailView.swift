import SwiftUI

struct RepositoryDetailView: View {
    let remoteURL: URL
    let remoteService: GitRemoteService
    @EnvironmentObject private var model: ProjectBrowserViewModel

    /// Defaults to real git, swapped for a fixture under a UI test — see `GitRemoteService`.
    init(remoteURL: URL, remoteService: GitRemoteService? = nil) {
        self.remoteURL = remoteURL
        self.remoteService = remoteService ?? GitRemoteServiceResolver().resolve()
    }

    var body: some View {
        RepositoryDetailContent(
            details: RepositoryDetailModel(remoteURL: remoteURL, store: model.store, remoteService: remoteService))
    }
}

private struct RepositoryDetailContent: View {
    @StateObject private var details: RepositoryDetailModel
    @State private var fullHistoryPhase: AsyncOperationPhase = .idle

    init(details: @autoclosure @escaping () -> RepositoryDetailModel) {
        _details = StateObject(wrappedValue: details())
    }

    var body: some View {
        let referencingCodebases = details.referencingCodebases
        Form {
            Section(.app("View.RepositoryDetailView.Repository")) {
                LabeledContent {
                    Text(verbatim: details.remoteURL.absoluteString)
                } label: {
                    Text(.app("View.RepositoryDetailView.Remote"))
                }
                LabeledContent {
                    if details.isLoadingDetails {
                        ProgressView()
                    } else {
                        Text(verbatim: details.onDiskSize.map(Self.byteCountFormatter.string(fromByteCount:)) ?? "—")
                            .accessibilityIdentifier("repository.diskSizeValue")
                    }
                } label: {
                    Text(.app("View.RepositoryDetailView.DiskSize"))
                }
                LabeledContent {
                    if details.isLoadingDetails {
                        ProgressView()
                    } else {
                        (details.lastFetchedAt.map { Text(verbatim: $0.formatted(.relative(presentation: .named))) }
                            ?? Text(.app("View.RepositoryDetailView.Never")))
                            .accessibilityIdentifier("repository.lastFetchedValue")
                    }
                } label: {
                    Text(.app("View.RepositoryDetailView.LastFetched"))
                }
                if details.isShallow {
                    LabeledContent {
                        Label(
                            .app("View.CodebaseDetailView.LatestSnapshotOnly"),
                            systemImage: "clock.badge.exclamationmark"
                        )
                        .accessibilityIdentifier("repository.latestSnapshotBadge")
                    } label: {
                        Text(.app("View.RepositoryDetailView.History"))
                    }
                    HStack {
                        FetchFullHistoryButton(
                            remoteURL: details.remoteURL, phase: $fullHistoryPhase,
                            identifierPrefix: "repository.fullHistory"
                        ) {
                            Task { await details.loadDetails() }
                        }
                    }
                }
            }

            Section(.app("View.RepositoryDetailView.Codebases \(referencingCodebases.count)")) {
                if referencingCodebases.isEmpty {
                    Text(.app("View.RepositoryDetailView.NoCodebasesReferenceRepository"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(referencingCodebases) { codebase in
                        Label(codebase.name, systemImage: "folder")
                            .accessibilityIdentifier("repository.codebase.\(codebase.name)")
                    }
                }
            }

            Section(.app("View.RepositoryDetailView.Worktrees \(details.worktreeNames.count)")) {
                if details.isLoadingDetails {
                    ProgressView()
                } else if details.worktreeNames.isEmpty {
                    Text(.app("View.RepositoryDetailView.NoLinkedWorktrees"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(details.worktreeNames, id: \.self) { name in
                        Label(name, systemImage: "arrow.triangle.branch")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(.app("View.RepositoryDetailView.Repository"))
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await details.fetchNow() }
                } label: {
                    Label(.app("View.RepositoryDetailView.FetchNow"), systemImage: "arrow.clockwise")
                }
                .disabled(details.isFetching)
                .accessibilityIdentifier("repository.fetchNowButton")
            }
        }
        .alert(
            .app("View.RepositoryDetailView.OperationFailed"),
            isPresented: Binding(
                get: { details.errorMessage != nil }, set: { if !$0 { details.errorMessage = nil } })
        ) {
            Button(.app("View.RepositoryDetailView.OK")) {}
        } message: {
            Text(verbatim: details.errorMessage ?? "")
        }
        .task { await details.loadDetails() }
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
