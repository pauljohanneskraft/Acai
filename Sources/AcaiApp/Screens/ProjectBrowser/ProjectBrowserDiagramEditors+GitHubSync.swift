import Foundation
import AcaiGit

// `codebase(for:)`/`projectID(for:)`/`mutateCodebase`/`persistProject` (defined in the main file)
// are no longer `private` so this extension can call them.
extension ProjectCodebaseEditor {
    // MARK: GitHub-backed codebases

    /// Clones `owner/repo` at `ref` into a shared, app-managed "hub" clone (reused by every
    /// codebase that references the same remote) and attaches a fresh linked worktree for this
    /// codebase, then indexes it — the GitHub equivalent of `addCodebase`. Two codebases pointing
    /// at the same remote share one on-disk object store and can sit at different commits
    /// simultaneously, each in its own worktree.
    func addGitHubCodebase(
        to projectID: UUID, name: String, credential: GitHubCredential, target: GitHubRepositoryRef
    ) async {
        guard let index = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        let codebaseID = UUID()
        let destination = GitWorktreeDestination(
            hubStoreDirectory: store.gitRepositoriesDir, worktreeName: store.gitWorktreeName(for: codebaseID),
            worktreeDirectory: store.gitWorktreeURL(for: codebaseID), locks: store.gitRepositoryLocks)
        // Captured into locals (rather than referenced via `self`/`store` inside the closure below)
        // so the closure passed to `activityCenter.run` — required `@Sendable` — only closes over
        // plain Sendable values, matching `reindex`'s existing `path`/`bookmark`/`fileFilter` pattern.
        let repositoryService = self.repositoryService
        let activityCenter = store.activityCenter
        do {
            let cloneResult = try await activityCenter.run(
                title: .app("Activity.Cloning \(target.owner)/\(target.repo)"),
                kind: .gitClone, subject: .codebase(codebaseID)
            ) { onProgress in
                let repositoryTarget = GitHubRepositoryTarget(
                    credential: credential, owner: target.owner, repo: target.repo, ref: target.ref)
                return try await repositoryService.attachWorktree(
                    repositoryTarget, destination: destination, onProgress: onProgress)
            }
            // Cancelled before finishing: don't add a `Codebase` for a clone we're pretending never
            // happened. `attachWorktree` itself doesn't observe cancellation (see `ActivityCenter
            // .run`'s doc comment), so a worktree may still land on disk in the background even
            // though nothing here ever references it — a known, stated limitation of "cancel" for
            // this operation kind until true mid-flight interruption is wired.
            guard let (headSHA, remoteURL) = cloneResult else { return }
            let codebase = Codebase(
                id: codebaseID,
                name: name,
                directoryPath: destination.worktreeDirectory.path,
                githubSource: GitHubSource(
                    owner: target.owner, repo: target.repo, ref: target.ref, refKind: target.kind,
                    lastSyncedCommitSHA: headSHA, lastSyncedAt: Date()),
                repository: CodebaseRepositoryReference(remoteURL: remoteURL, ref: target.ref)
            )
            store.projects[index].codebases.append(codebase)
            persist()
            await reindex(codebaseID: codebaseID)
        } catch {
            store.report(.app("Error.ProjectBrowserViewModel.CloneFailed \(error.localizedDescription)"))
        }
    }

    /// Re-syncs a GitHub-backed codebase against its stored ref, then reindexes if the upstream
    /// head commit has actually moved. An incremental fetch is cheap enough to just always run,
    /// rather than pre-checking via a separate REST call.
    func pull(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID), let source = codebase.githubSource else { return }
        guard let account = GitHubTokenStore().load() else {
            store.report(.app("Error.ProjectBrowserViewModel.SignInToPull \(source.owner)/\(source.repo)"))
            return
        }
        // Extracted into locals before the `@Sendable` closure below — see `addGitHubCodebase`'s
        // identical comment for why (avoids capturing `self`/`store`, neither Sendable).
        let repositoryService = self.repositoryService
        let usesWorktree = codebase.repository != nil
        let worktreeDestination = worktreeDestination(codebaseID: codebaseID)
        let legacyCloneURL = store.githubCloneURL(for: codebaseID)
        do {
            let fetchResult = try await store.activityCenter.run(
                title: .app("Activity.Fetching \(source.owner)/\(source.repo)"),
                kind: .gitFetch, subject: .codebase(codebaseID)
            ) { onProgress throws -> String in
                let target = GitHubRepositoryTarget(
                    credential: account.credential, owner: source.owner, repo: source.repo, ref: source.ref)
                if usesWorktree {
                    // Fetch the shared hub clone and move this codebase's own worktree along with it.
                    return try await repositoryService.resyncWorktree(
                        target, destination: worktreeDestination, onProgress: onProgress)
                } else {
                    // A codebase created before worktree support existed: still an independent
                    // clone under `githubClonesDir`.
                    return try await repositoryService.sync(target, into: legacyCloneURL, onProgress: onProgress)
                }
            }
            // Cancelled before finishing: don't stamp a new `lastSyncedCommitSHA`/reindex against a
            // fetch we can't be sure fully landed.
            guard let latestSHA = fetchResult else { return }
            guard latestSHA != source.lastSyncedCommitSHA else { return }
            mutateCodebase(codebaseID) {
                $0.githubSource?.lastSyncedCommitSHA = latestSHA
                $0.githubSource?.lastSyncedAt = Date()
            }
            await reindex(codebaseID: codebaseID)
        } catch {
            store.report(.app("Error.ProjectBrowserViewModel.PullFailed \(error.localizedDescription)"))
        }
    }

    /// Switches a GitHub-backed codebase to a different branch/tag: updates the stored ref and
    /// forces a resync (bypassing the "unchanged head" short-circuit `pull` uses above, since the
    /// ref itself just changed). Mirrors `pull`'s ordering above: the stored ref only changes once
    /// the resync against it has actually succeeded, so a failed switch leaves the codebase on its
    /// previous (still-valid) ref instead of pointing at a ref its on-disk content doesn't match.
    func switchGitHubRef(codebaseID: UUID, ref: String, kind: GitHubRef.Kind) async {
        guard let codebase = codebase(for: codebaseID), let source = codebase.githubSource else { return }
        guard let account = GitHubTokenStore().load() else {
            store.report(.app("Error.ProjectBrowserViewModel.SignInToSwitchBranches"))
            return
        }
        // Extracted into locals before the `@Sendable` closure below — see `addGitHubCodebase`'s
        // identical comment for why (avoids capturing `self`/`store`, neither Sendable).
        let repositoryService = self.repositoryService
        let usesWorktree = codebase.repository != nil
        let worktreeDestination = worktreeDestination(codebaseID: codebaseID)
        let legacyCloneURL = store.githubCloneURL(for: codebaseID)
        do {
            let switchResult = try await store.activityCenter.run(
                title: .app("Activity.Switching \(source.owner)/\(source.repo) \(ref)"),
                kind: .gitFetch, subject: .codebase(codebaseID)
            ) { onProgress throws -> String in
                let target = GitHubRepositoryTarget(
                    credential: account.credential, owner: source.owner, repo: source.repo, ref: ref)
                if usesWorktree {
                    return try await repositoryService.resyncWorktree(
                        target, destination: worktreeDestination, onProgress: onProgress)
                } else {
                    return try await repositoryService.sync(target, into: legacyCloneURL, onProgress: onProgress)
                }
            }
            // Cancelled before finishing: leave the codebase on its previous, still-valid ref rather
            // than stamping a switch that may not have actually landed.
            guard let headSHA = switchResult else { return }
            mutateCodebase(codebaseID) {
                $0.githubSource?.ref = ref
                $0.githubSource?.refKind = kind
                $0.githubSource?.lastSyncedCommitSHA = headSHA
                $0.githubSource?.lastSyncedAt = Date()
                $0.repository?.ref = ref
            }
            await reindex(codebaseID: codebaseID)
        } catch {
            store.report(.app("Error.ProjectBrowserViewModel.BranchSwitchFailed \(error.localizedDescription)"))
        }
    }

    /// The credentialed transport URL to actually fetch/checkout over is built separately, inside
    /// `GitHubRepositoryService`, from the caller's own `owner`/`repo`/`credential`.
    private func worktreeDestination(codebaseID: UUID) -> GitWorktreeDestination {
        GitWorktreeDestination(
            hubStoreDirectory: store.gitRepositoriesDir, worktreeName: store.gitWorktreeName(for: codebaseID),
            worktreeDirectory: store.gitWorktreeURL(for: codebaseID), locks: store.gitRepositoryLocks)
    }

    func reindex(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID) else { return }
        let path = codebase.directoryPath
        let bookmark = codebase.securityScopedBookmark
        let fileFilter = codebase.fileFilter
        let analyzer = CodebaseAnalyzingResolver().resolve(codebaseID: codebaseID)
        let store = store
        do {
            // `refreshedBookmark` is populated (and only read) inside this single detached
            // closure's own synchronous execution, then handed back through the return value —
            // never captured mutably across the concurrency boundary.
            //
            // Registered with `activityCenter` so this shows up in the Activity indicator and flips
            // the codebase row's checkmark to a spinner for as long as it runs. `Task.detached`
            // doesn't inherit cancellation from its parent, so the detached parse is explicitly
            // cancelled via `withTaskCancellationHandler` when the wrapping `run` task is cancelled
            // — `AnalysisService.parseFiles` then observes it between files (`Task.checkCancellation`)
            // and the parse actually stops, rather than merely having its result discarded.
            //
            // The artifact is saved to disk (awaited) *inside* this closure, before `run` returns —
            // otherwise `isBusy`/the row's spinner would flip to "done" before the write lands.
            let reindexResult = try await store.activityCenter.run(
                title: .app("Activity.Indexing \(codebase.name)"),
                kind: .reindex, subject: .codebase(codebaseID)
            ) {
                let detached = Task.detached(priority: .userInitiated) {
                    var refreshed: ScopedResourceAccess.Refreshed?
                    let artifact = try ScopedResourceAccess(path: path, bookmark: bookmark).withResolvedURL(
                        onRefresh: { refreshed = $0 },
                        { url in try analyzer.enrichedArtifact(at: url, fileFilter: fileFilter) }
                    )
                    return (artifact, refreshed)
                }
                let (artifact, refreshed) = try await withTaskCancellationHandler {
                    try await detached.value
                } onCancel: {
                    detached.cancel()
                }
                try await store.saveArtifactAndWait(artifact, for: codebaseID)
                return (artifact, refreshed)
            }
            // Cancelled before finishing: don't apply a result we discarded.
            guard let (newArtifact, refreshed) = reindexResult else { return }
            // Re-resolve indices after the suspension — the user may have mutated the project/codebase
            // list during the (potentially long) analysis, invalidating any pre-`await` indices.
            guard let pIndex = store.projects.firstIndex(where: { $0.id == projectID(for: codebaseID) }),
                  let cIndex = store.projects[pIndex].codebases.firstIndex(where: { $0.id == codebaseID })
            else { return }
            store.projects[pIndex].codebases[cIndex].hasArtifact = true
            store.projects[pIndex].codebases[cIndex].lastIndexed = Date()
            store.projects[pIndex].codebases[cIndex].hasParseErrors = newArtifact.metadata.hasParseErrors
            store.projects[pIndex].codebases[cIndex].parseDiagnosticCount = newArtifact.metadata.parseDiagnostics.count
            // A bookmark follows a folder that was moved or renamed, so the stored path has to
            // move with it — it's what the UI shows and what the file watcher opens.
            if let refreshed {
                store.projects[pIndex].codebases[cIndex].securityScopedBookmark = refreshed.bookmark
                store.projects[pIndex].codebases[cIndex].directoryPath = refreshed.url.path
            }
            persistProject(store.projects[pIndex].id)
            triggerSpotlightReindex()
        } catch {
            // An app-managed directory (a GitHub clone or worktree) must never be re-pointed at a
            // folder of the user's choosing — only a codebase they picked themselves.
            let relocatable = error is ScopedResourceAccess.Failure && codebase.githubSource == nil
            store.report(
                .app("Error.ProjectBrowserViewModel.ReindexFailed \(error.localizedDescription)"),
                relocating: relocatable ? codebaseID : nil)
        }
    }
}
