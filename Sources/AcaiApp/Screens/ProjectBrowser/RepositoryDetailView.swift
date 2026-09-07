import AcaiGit
import SwiftUI

struct RepositoryDetailView: View {
    let remoteURL: URL
    @EnvironmentObject private var model: ProjectBrowserViewModel

    @State private var onDiskSize: Int64?
    @State private var lastFetchedAt: Date?
    @State private var worktreeNames: [String] = []
    @State private var isFetching = false
    @State private var isRemoving = false
    @State private var isLoadingDetails = false
    @State private var removalBlockedMessage: LocalizedStringResource?
    @State private var showRemoveConfirmation = false
    @State private var errorMessage: String?

    private var hub: GitRepository {
        GitRepository(remoteURL: remoteURL, storeDirectory: model.store.gitRepositoriesDir)
    }

    private var referencingCodebases: [Codebase] {
        model.repositoryIndex().first { $0.remoteURL == remoteURL }?.codebases ?? []
    }

    var body: some View {
        let referencingCodebases = referencingCodebases
        Form {
            Section(.app("View.RepositoryDetailView.Repository")) {
                LabeledContent {
                    Text(verbatim: remoteURL.absoluteString)
                } label: {
                    Text(.app("View.RepositoryDetailView.Remote"))
                }
                LabeledContent {
                    if isLoadingDetails {
                        ProgressView()
                    } else {
                        Text(verbatim: onDiskSize.map(Self.byteCountFormatter.string(fromByteCount:)) ?? "—")
                    }
                } label: {
                    Text(.app("View.RepositoryDetailView.DiskSize"))
                }
                LabeledContent {
                    if isLoadingDetails {
                        ProgressView()
                    } else {
                        lastFetchedAt.map { Text(verbatim: $0.formatted(.relative(presentation: .named))) }
                            ?? Text(.app("View.RepositoryDetailView.Never"))
                    }
                } label: {
                    Text(.app("View.RepositoryDetailView.LastFetched"))
                }
            }

            Section(.app("View.RepositoryDetailView.Codebases \(referencingCodebases.count)")) {
                if referencingCodebases.isEmpty {
                    Text(.app("View.RepositoryDetailView.NoCodebasesReferenceRepository"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(referencingCodebases) { codebase in
                        Label(codebase.name, systemImage: "folder")
                    }
                }
            }

            Section(.app("View.RepositoryDetailView.Worktrees \(worktreeNames.count)")) {
                if isLoadingDetails {
                    ProgressView()
                } else if worktreeNames.isEmpty {
                    Text(.app("View.RepositoryDetailView.NoLinkedWorktrees"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(worktreeNames, id: \.self) { name in
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
                    Task { await fetchNow() }
                } label: {
                    Label(.app("View.RepositoryDetailView.FetchNow"), systemImage: "arrow.clockwise")
                }
                .disabled(isFetching || isRemoving)
                .accessibilityIdentifier("repository.fetchNowButton")
            }
            ToolbarItem {
                Button(role: .destructive) {
                    attemptRemove(referencingCodebases)
                } label: {
                    Label(.app("View.RepositoryDetailView.Remove"), systemImage: "trash")
                }
                .disabled(isFetching || isRemoving)
                .accessibilityIdentifier("repository.removeButton")
            }
        }
        .confirmationDialog(
            .app("View.RepositoryDetailView.RemoveRepository"),
            isPresented: $showRemoveConfirmation
        ) {
            Button(.app("View.RepositoryDetailView.Remove"), role: .destructive) { Task { await remove() } }
                .accessibilityIdentifier("repository.remove.confirmButton")
        } message: {
            Text(.app("View.RepositoryDetailView.DeletesSharedCloneDisk"))
        }
        .alert(
            .app("View.RepositoryDetailView.CanRemoveRepository"),
            isPresented: Binding(get: { removalBlockedMessage != nil }, set: { if !$0 { removalBlockedMessage = nil } })
        ) {
            Button(.app("View.RepositoryDetailView.OK")) {}
        } message: {
            removalBlockedMessage.map(Text.init)
        }
        .alert(
            .app("View.RepositoryDetailView.OperationFailed"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(.app("View.RepositoryDetailView.OK")) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .task(id: remoteURL) { await loadDetails() }
    }

    private func loadDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        let hub = hub
        let (size, fetchedAt, names) = await Task.detached(priority: .userInitiated) {
            (hub.onDiskSize, hub.lastFetchedAt, (try? GitWorktree(repositoryDirectory: hub.localPath).list()) ?? [])
        }.value
        onDiskSize = size
        lastFetchedAt = fetchedAt
        worktreeNames = names.sorted()
    }

    private func fetchNow() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        let hub = hub
        let locks = model.store.gitRepositoryLocks
        let remoteURL = remoteURL
        do {
            // Registered with `activityCenter` — shows up in the global Activity indicator and
            // flips this repository's row (in the sidebar's Repositories section) to a spinner,
            // the same as a codebase's reindex/fetch does.
            _ = try await model.store.activityCenter.run(
                title: .app("Activity.FetchingRemote \(remoteURL.lastPathComponent)"),
                kind: .gitFetch, subject: .repository(remoteURL)
            ) { onProgress in
                try await locks.run(for: hub) {
                    try await hub.fetch(onProgress: onProgress)
                }
            }
            await loadDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attemptRemove(_ referencingCodebases: [Codebase]) {
        guard referencingCodebases.isEmpty else {
            let names = referencingCodebases.map(\.name).sorted().joined(separator: ", ")
            let count = referencingCodebases.count
            removalBlockedMessage = .app("View.RepositoryDetailView.RemovalBlocked \(names) \(count)")
            return
        }
        showRemoveConfirmation = true
    }

    private func remove() async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        let hub = hub
        let locks = model.store.gitRepositoryLocks
        do {
            try await locks.run(for: hub) {
                try FileManager.default.removeItem(at: hub.localPath)
            }
            model.selection = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
