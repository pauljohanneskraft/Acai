import AcaiGit
import SwiftUI

/// The Repositories detail pane: one shared `AcaiGit.GitRepository`'s remote URL, on-disk size,
/// last-fetched time, and every codebase (across every project) referencing it — plus Fetch
/// now/Manage worktrees/Remove actions.
struct RepositoryDetailView: View {
    let remoteURL: URL
    @EnvironmentObject private var model: ProjectBrowserViewModel

    @State private var onDiskSize: Int64?
    @State private var lastFetchedAt: Date?
    @State private var worktreeNames: [String] = []
    @State private var isFetching = false
    @State private var isRemoving = false
    @State private var isLoadingDetails = false
    @State private var removalBlockedMessage: String?
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
            Section("Repository") {
                LabeledContent("Remote", value: remoteURL.absoluteString)
                LabeledContent("On-disk size") {
                    if isLoadingDetails {
                        ProgressView()
                    } else {
                        Text(onDiskSize.map(Self.byteCountFormatter.string(fromByteCount:)) ?? "—")
                    }
                }
                LabeledContent("Last fetched") {
                    if isLoadingDetails {
                        ProgressView()
                    } else {
                        Text(lastFetchedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                    }
                }
            }

            Section("Codebases (\(referencingCodebases.count))") {
                if referencingCodebases.isEmpty {
                    Text("No codebases reference this repository.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(referencingCodebases) { codebase in
                        Label(codebase.name, systemImage: "folder")
                    }
                }
            }

            Section("Worktrees (\(worktreeNames.count))") {
                if isLoadingDetails {
                    ProgressView()
                } else if worktreeNames.isEmpty {
                    Text("No linked worktrees.")
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
        .navigationTitle("Repository")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await fetchNow() }
                } label: {
                    Label("Fetch Now", systemImage: "arrow.clockwise")
                }
                .disabled(isFetching || isRemoving)
                .accessibilityIdentifier("repository.fetchNowButton")
            }
            ToolbarItem {
                Button(role: .destructive) {
                    attemptRemove(referencingCodebases)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(isFetching || isRemoving)
                .accessibilityIdentifier("repository.removeButton")
            }
        }
        .confirmationDialog(
            "Remove this repository?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) { Task { await remove() } }
                .accessibilityIdentifier("repository.remove.confirmButton")
        } message: {
            Text("This deletes its shared clone from disk. This cannot be undone.")
        }
        .alert(
            "Can't Remove Repository",
            isPresented: Binding(get: { removalBlockedMessage != nil }, set: { if !$0 { removalBlockedMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(removalBlockedMessage ?? "")
        }
        .alert(
            "Operation Failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
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
                title: "Fetching \(remoteURL.lastPathComponent)…", kind: .gitFetch, subject: .repository(remoteURL)
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
            removalBlockedMessage =
                "Remove or reassign \(names) first — this repository is still referenced by "
                + "\(referencingCodebases.count == 1 ? "1 codebase" : "\(referencingCodebases.count) codebases")."
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
