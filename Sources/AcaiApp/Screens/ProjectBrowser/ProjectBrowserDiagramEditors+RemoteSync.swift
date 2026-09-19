import Foundation
import AcaiCore
import AcaiGit

// `codebase(for:)`/`projectID(for:)`/`mutateCodebase`/`persistProject` (defined in the main file)
// are no longer `private` so this extension can call them.
extension ProjectCodebaseEditor {
    // MARK: Managed checkouts of a remote

    /// Clones `remoteURL` into a shared, app-managed "hub" clone (reused by every codebase that
    /// references the same remote), attaches a fresh linked worktree for this codebase at `ref`,
    /// then indexes it. Works for any git remote; a GitHub token is used only for GitHub.
    func addRemoteCodebase(
        to projectID: UUID, name: String, remoteURL: URL, ref: String, refKind: GitCheckout.Ref.Kind,
        depth: GitHistoryDepth = .full
    ) async {
        guard store.projects.contains(where: { $0.id == projectID }) else { return }
        let codebaseID = UUID()
        let destination = worktreeDestination(codebaseID: codebaseID)
        let endpoint = RemoteEndpoint(remoteURL: remoteURL)
        let target = RemoteCheckoutTarget(endpoint: endpoint, ref: ref, depth: depth)
        // Locals, not `self`/`store`, so the `@Sendable` closure below closes over Sendable values only.
        let remoteService = self.remoteService
        do {
            let cloneResult = try await store.activityCenter.run(
                title: .app("Activity.CloningRemote \(remoteDisplayName(remoteURL))"),
                kind: .gitClone, subject: .codebase(codebaseID)
            ) { onProgress in
                try await remoteService.attachWorktree(target, destination: destination, onProgress: onProgress)
            }
            guard let (headSHA, persistedRemoteURL) = cloneResult,
                  let index = store.projects.firstIndex(where: { $0.id == projectID })
            else { return }
            store.projects[index].codebases.append(Codebase(
                id: codebaseID,
                name: name,
                directoryPath: destination.worktreeDirectory.path,
                managedCheckout: ManagedCheckout(
                    refKind: refKind, lastSyncedCommitSHA: headSHA, lastSyncedAt: Date()),
                repository: CodebaseRepositoryReference(remoteURL: persistedRemoteURL, ref: ref)
            ))
            persist()
            await reindex(codebaseID: codebaseID)
        } catch {
            report(error, for: endpoint, generic: { .app("Error.ProjectBrowserViewModel.CloneFailed \($0)") })
        }
    }

    /// Fetches a managed codebase's remote and moves it to the latest commit of its ref, then
    /// reindexes if that commit actually moved.
    func pull(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID), let checkout = codebase.managedCheckout,
              let repository = codebase.repository
        else { return }
        let target = RemoteCheckoutTarget(
            endpoint: RemoteEndpoint(remoteURL: repository.remoteURL), ref: repository.ref)
        do {
            let fetchResult = try await store.activityCenter.run(
                title: .app("Activity.FetchingRemote \(repository.remoteDisplayName)"),
                kind: .gitFetch, subject: .codebase(codebaseID),
                resyncOperation(codebase: codebase, target: target)
            )
            guard let latestSHA = fetchResult, latestSHA != checkout.lastSyncedCommitSHA else { return }
            mutateCodebase(codebaseID) {
                $0.managedCheckout?.lastSyncedCommitSHA = latestSHA
                $0.managedCheckout?.lastSyncedAt = Date()
            }
            await reindex(codebaseID: codebaseID)
        } catch {
            report(error, for: target.endpoint, generic: { .app("Error.ProjectBrowserViewModel.PullFailed \($0)") })
        }
    }

    /// Moves a managed codebase to another branch or tag. The stored ref only changes once the
    /// checkout against it has succeeded, so a failed switch leaves the codebase on its previous,
    /// still-valid ref.
    func switchRef(codebaseID: UUID, ref: String, kind: GitCheckout.Ref.Kind) async {
        guard let codebase = codebase(for: codebaseID), codebase.managedCheckout != nil,
              let repository = codebase.repository
        else { return }
        let target = RemoteCheckoutTarget(endpoint: RemoteEndpoint(remoteURL: repository.remoteURL), ref: ref)
        do {
            let switchResult = try await store.activityCenter.run(
                title: .app("Activity.SwitchingRemote \(repository.remoteDisplayName) \(ref)"),
                kind: .gitFetch, subject: .codebase(codebaseID),
                resyncOperation(codebase: codebase, target: target)
            )
            guard let headSHA = switchResult else { return }
            mutateCodebase(codebaseID) {
                $0.managedCheckout?.refKind = kind
                $0.managedCheckout?.lastSyncedCommitSHA = headSHA
                $0.managedCheckout?.lastSyncedAt = Date()
                $0.repository?.ref = ref
            }
            await reindex(codebaseID: codebaseID)
        } catch {
            report(
                error, for: target.endpoint,
                generic: { .app("Error.ProjectBrowserViewModel.BranchSwitchFailed \($0)") })
        }
    }

    /// Deepens a shallow clone to its complete history, so history-dependent features can answer.
    /// `false` when it didn't finish; a failure has already been reported.
    @discardableResult
    func fetchFullHistory(remoteURL: URL) async -> Bool {
        let endpoint = RemoteEndpoint(remoteURL: remoteURL)
        let remoteService = self.remoteService
        let hubStoreDirectory = store.gitRepositoriesDir
        let locks = store.gitRepositoryLocks
        do {
            let finished = try await store.activityCenter.run(
                title: .app("Activity.FetchingFullHistory \(remoteDisplayName(remoteURL))"),
                kind: .gitFetch, subject: .repository(remoteURL)
            ) { onProgress in
                try await remoteService.fetchFullHistory(
                    endpoint, hubStoreDirectory: hubStoreDirectory, locks: locks, onProgress: onProgress)
            } != nil
            notify()
            return finished
        } catch {
            report(
                error, for: endpoint,
                generic: { .app("Error.ProjectBrowserViewModel.FetchFullHistoryFailed \($0)") })
            return false
        }
    }

    private func resyncOperation(
        codebase: Codebase, target: RemoteCheckoutTarget
    ) -> @Sendable (@escaping @Sendable (Double) -> Void) async throws -> String {
        let remoteService = self.remoteService
        let destination = worktreeDestination(codebaseID: codebase.id)
        return { onProgress in
            try await remoteService.resyncWorktree(target, destination: destination, onProgress: onProgress)
        }
    }

    /// A rejected request to GitHub while signed out most likely means a private repository, which
    /// signing in fixes — say so rather than only relaying the transport error.
    private func report(
        _ error: Error, for endpoint: RemoteEndpoint, generic: (String) -> LocalizedStringResource
    ) {
        let detail = error.localizedDescription
        if case .github = endpoint.host, endpoint.transportURL == endpoint.remoteURL {
            store.report(.app("Error.ProjectBrowserViewModel.SignInToGitHubMayHelp \(detail)"))
        } else {
            store.report(generic(detail))
        }
    }

    private func remoteDisplayName(_ remoteURL: URL) -> String {
        CodebaseRepositoryReference(remoteURL: remoteURL, ref: "").remoteDisplayName
    }

    private func worktreeDestination(codebaseID: UUID) -> GitWorktreeDestination {
        GitWorktreeDestination(
            hubStoreDirectory: store.gitRepositoriesDir, worktreeName: store.gitWorktreeName(for: codebaseID),
            worktreeDirectory: store.gitWorktreeURL(for: codebaseID), locks: store.gitRepositoryLocks)
    }
}
