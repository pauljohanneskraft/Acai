import AcaiGit
import SwiftUI

/// A local folder's branches and tags, and what is checked out in it right now.
struct LocalRevisions: Equatable {
    var refs: [GitCheckout.Ref]
    var checkedOut: String?
}

extension CodebaseDetailView {

    // MARK: - Managed checkout

    @ViewBuilder
    func managedCheckoutActions(codebase: Codebase, repository: CodebaseRepositoryReference) -> some View {
        let refKind = codebase.managedCheckout?.refKind ?? .branch
        let current = GitCheckout.Ref(name: repository.ref, kind: refKind)
        if isShallowClone {
            latestSnapshotBadge(remoteURL: repository.remoteURL)
        }
        Picker(.app("View.CodebaseDetailView.BranchTag"), selection: Binding(
            get: { current.id },
            set: { newID in
                guard let selected = (availableRefs + [current]).first(where: { $0.id == newID }),
                      selected != current
                else { return }
                refSwitchPhase = .loading(.app("View.CodebaseDetailView.SwitchingTo \(selected.name)"))
                Task {
                    await model.editing.switchRef(codebaseID: codebase.id, ref: selected.name, kind: selected.kind)
                    refSwitchPhase = .loaded
                }
            }
        )) {
            if !availableRefs.contains(current) {
                Text(verbatim: current.name).tag(current.id)
            }
            ForEach(availableRefs) { ref in
                Text(verbatim: ref.name).tag(ref.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .disabled(refSwitchPhase.isInFlight)
        .accessibilityIdentifier("codebaseDetail.refPicker")
        .task(id: ManagedCheckoutToken(
            remoteURL: repository.remoteURL, lastSynced: codebase.managedCheckout?.lastSyncedAt
        )) {
            await loadManagedCheckoutState(repository: repository)
        }
        AsyncOperationStatusView(identifierPrefix: "codebaseDetail.refSwitch", phase: refSwitchPhase)

        Button {
            pullPhase = .loading(.app("View.CodebaseDetailView.Pulling"))
            Task {
                await model.editing.pull(codebaseID: codebase.id)
                pullPhase = .loaded
            }
        } label: {
            Label(.app("View.CodebaseDetailView.Pull"), systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(pullPhase.isInFlight)
        .accessibilityIdentifier("codebaseDetail.pullButton")
        AsyncOperationStatusView(identifierPrefix: "codebaseDetail.pull", phase: pullPhase)
    }

    private struct ManagedCheckoutToken: Equatable {
        let remoteURL: URL
        let lastSynced: Date?
    }

    private func loadManagedCheckoutState(repository: CodebaseRepositoryReference) async {
        let endpoint = RemoteEndpoint(remoteURL: repository.remoteURL, gitHubCredential: nil)
        let hubStoreDirectory = model.store.gitRepositoriesDir
        availableRefs = (try? await remoteService.refs(of: endpoint, hubStoreDirectory: hubStoreDirectory)) ?? []
        let hub = GitRepository(remoteURL: repository.remoteURL, storeDirectory: hubStoreDirectory)
        isShallowClone = await Task.detached(priority: .utility) { hub.isShallow }.value
    }

    /// Says the clone carries only the latest snapshot, with the action that fetches the rest.
    private func latestSnapshotBadge(remoteURL: URL) -> some View {
        HStack(spacing: 6) {
            Label(.app("View.CodebaseDetailView.LatestSnapshotOnly"), systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(.app("View.CodebaseDetailView.LatestSnapshotOnlyHelp"))
                .accessibilityIdentifier("codebaseDetail.latestSnapshotBadge")
            FetchFullHistoryButton(
                remoteURL: remoteURL, phase: $fullHistoryPhase, identifierPrefix: "codebaseDetail.fullHistory"
            ) {
                isShallowClone = false
            }
        }
    }

    // MARK: - Local folder revision

    /// Offered only when the folder is inside a git repository. Picking a revision reads it from the
    /// repository's history; the folder and whatever is checked out in it are left alone.
    @ViewBuilder
    func localRevisionPicker(codebase: Codebase) -> some View {
        Group {
            if let localRevisions, !localRevisions.refs.isEmpty {
                Picker(.app("View.CodebaseDetailView.AnalysedRevision"), selection: Binding(
                    get: { codebase.analysedRevision },
                    set: { revision in
                        refSwitchPhase = .loading(.app("View.CodebaseDetailView.Indexing"))
                        Task {
                            await model.editing.setAnalysedRevision(revision, codebaseID: codebase.id)
                            refSwitchPhase = .loaded
                        }
                    }
                )) {
                    Text(.app("View.CodebaseDetailView.WorkingTree")).tag(String?.none)
                    if let pinned = codebase.analysedRevision,
                       !localRevisions.refs.contains(where: { $0.name == pinned }) {
                        Text(verbatim: pinned).tag(Optional(pinned))
                    }
                    ForEach(localRevisions.refs) { ref in
                        Text(verbatim: ref.name).tag(Optional(ref.name))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                .disabled(refSwitchPhase.isInFlight)
                .help(.app("View.CodebaseDetailView.AnalysedRevisionHelp"))
                .accessibilityIdentifier("codebaseDetail.revisionPicker")
                AsyncOperationStatusView(identifierPrefix: "codebaseDetail.revisionSwitch", phase: refSwitchPhase)
            }
        }
        .task(id: codebase.id) { await loadLocalRevisions(codebase: codebase) }
    }

    func pinnedRevisionCaption(revision: String) -> some View {
        let checkedOut = localRevisions?.checkedOut ?? "—"
        return Label(
            .app("View.CodebaseDetailView.AnalysingRevision \(revision) \(checkedOut)"),
            systemImage: "clock"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("codebaseDetail.pinnedRevisionCaption")
    }

    private func loadLocalRevisions(codebase: Codebase) async {
        let access = ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
        localRevisions = await Task.detached(priority: .utility) { () -> LocalRevisions? in
            let revisions = try? access.withResolvedURL { url -> LocalRevisions? in
                guard let checkout = try? GitCheckout(directory: url) else { return nil }
                return LocalRevisions(refs: (try? checkout.refs()) ?? [], checkedOut: try? checkout.currentRef)
            }
            return revisions.flatMap { $0 }
        }.value
    }
}

/// Deepens a shallow clone. Shared by every surface that says history isn't available yet.
struct FetchFullHistoryButton: View {
    let remoteURL: URL
    @Binding var phase: AsyncOperationPhase
    let identifierPrefix: String
    var onFetched: () -> Void = {}
    @EnvironmentObject private var model: ProjectBrowserViewModel

    var body: some View {
        Button(action: fetch) {
            Label(.app("View.FetchFullHistoryButton.FetchFullHistory"), systemImage: "clock.arrow.circlepath")
        }
        .disabled(phase.isInFlight)
        .accessibilityIdentifier("\(identifierPrefix)Button")
        .contextMenu {
            Button(action: fetch) {
                Label(.app("View.FetchFullHistoryButton.FetchFullHistory"), systemImage: "clock.arrow.circlepath")
            }
        }
        AsyncOperationStatusView(identifierPrefix: identifierPrefix, phase: phase)
    }

    private func fetch() {
        guard !phase.isInFlight else { return }
        phase = .loading(.app("View.FetchFullHistoryButton.Fetching"))
        Task {
            if await model.editing.fetchFullHistory(remoteURL: remoteURL) {
                phase = .loaded
                onFetched()
            } else {
                phase = .failed(String(localized: .app("View.FetchFullHistoryButton.Failed")))
            }
        }
    }
}
