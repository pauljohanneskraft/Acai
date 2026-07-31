import Foundation
import AcaiGit

// `ProjectCodebaseEditor`'s GitHub-sync concern (clone/pull/switch-ref, all funneling into
// `reindex`), carved out of `ProjectBrowserDiagramEditors.swift` to keep that file under the
// project's file-length limit — mirrors `ProjectBrowserView+Repositories.swift`'s identical reason
// for existing as a separate file. `codebase(for:)`/`projectID(for:)`/`mutateCodebase`/
// `persistProject` (defined in the main file) are no longer `private` so this extension can call
// them — same "not private, another file's extension needs it too" pattern used throughout this
// app (see `ProjectBrowserView`'s own stored properties for precedent).
extension ProjectCodebaseEditor {
    // MARK: GitHub-backed codebases

    /// Clones `owner/repo` at `ref` into a shared, app-managed "hub" clone (reused by every
    /// codebase that references the same remote) and attaches a fresh linked worktree for
    /// this codebase, then indexes it — the GitHub equivalent of `addCodebase`. Two codebases
    /// pointing at the same remote share one on-disk object store and can sit at different commits
    /// simultaneously, each in its own worktree — this is true uniformly, whether this is the
    /// first codebase ever to reference this remote or the fifth.
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
                title: "Cloning \(target.owner)/\(target.repo)…", kind: .gitClone, subject: .codebase(codebaseID)
            ) {
                try await repositoryService.attachWorktree(
                    credential: credential, owner: target.owner, repo: target.repo, ref: target.ref,
                    destination: destination)
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
            store.report("Clone failed: \(error.localizedDescription)")
        }
    }

    /// Re-syncs a GitHub-backed codebase against its stored ref, then reindexes if the upstream
    /// head commit has actually moved. An incremental fetch is cheap enough to just always run,
    /// rather than pre-checking via a separate REST call.
    func pull(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID), let source = codebase.githubSource else { return }
        guard let account = GitHubTokenStore().load() else {
            store.report("Sign in to GitHub to pull \(source.owner)/\(source.repo).")
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
                title: "Fetching \(source.owner)/\(source.repo)…", kind: .gitFetch, subject: .codebase(codebaseID)
            ) { () throws -> String in
                if usesWorktree {
                    // Fetch the shared hub clone and move this codebase's own worktree along with it.
                    return try await repositoryService.resyncWorktree(
                        credential: account.credential, owner: source.owner, repo: source.repo, ref: source.ref,
                        destination: worktreeDestination)
                } else {
                    // A codebase created before worktree support existed: still an independent
                    // clone under `githubClonesDir`.
                    return try await repositoryService.sync(
                        credential: account.credential, owner: source.owner, repo: source.repo, ref: source.ref,
                        into: legacyCloneURL)
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
            store.report("Pull failed: \(error.localizedDescription)")
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
            store.report("Sign in to GitHub to switch branches.")
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
                title: "Switching \(source.owner)/\(source.repo) to \(ref)…",
                kind: .gitFetch, subject: .codebase(codebaseID)
            ) { () throws -> String in
                if usesWorktree {
                    return try await repositoryService.resyncWorktree(
                        credential: account.credential, owner: source.owner, repo: source.repo, ref: ref,
                        destination: worktreeDestination)
                } else {
                    return try await repositoryService.sync(
                        credential: account.credential, owner: source.owner, repo: source.repo, ref: ref,
                        into: legacyCloneURL)
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
            store.report("Branch switch failed: \(error.localizedDescription)")
        }
    }

    /// Bundles `codebaseID`'s worktree location + the shared locks for a `resyncWorktree` call. The
    /// credentialed transport URL to actually fetch/checkout over is built separately, inside
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
        do {
            // `refreshedBookmark` is populated (and only read) inside this single detached
            // closure's own synchronous execution, then handed back through the return value —
            // never captured mutably across the concurrency boundary.
            //
            // Registered with `activityCenter` so this shows up in the Activity indicator and flips
            // the codebase row's checkmark to a spinner for as long as it runs. Cancelling it here
            // only discards the result below (`reindexResult == nil`) — `CodebaseAnalyzer`'s parse
            // pass doesn't poll `Task.isCancelled` internally (verified by inspection, not assumed),
            // so the detached parse keeps running to completion in the background even after Cancel
            // is tapped. Real mid-flight interruption is a separate, not-yet-built piece of work.
            let reindexResult = try await store.activityCenter.run(
                title: "Indexing \(codebase.name)…", kind: .reindex, subject: .codebase(codebaseID)
            ) {
                try await Task.detached(priority: .userInitiated) {
                    var refreshedBookmark: SecurityScopedBookmark?
                    let artifact = try ScopedResourceAccess(path: path, bookmark: bookmark).withResolvedURL(
                        onRefresh: { refreshedBookmark = $0 },
                        { url in try CodebaseAnalyzer().enrichedArtifact(at: url, fileFilter: fileFilter) }
                    )
                    return (artifact, refreshedBookmark)
                }.value
            }
            // Cancelled before finishing: don't apply a result we discarded.
            guard let (newArtifact, refreshedBookmark) = reindexResult else { return }
            // Re-resolve indices after the suspension — the user may have mutated the project/codebase
            // list during the (potentially long) analysis, invalidating any pre-`await` indices.
            guard let pIndex = store.projects.firstIndex(where: { $0.id == projectID(for: codebaseID) }),
                  let cIndex = store.projects[pIndex].codebases.firstIndex(where: { $0.id == codebaseID })
            else { return }
            store.projects[pIndex].codebases[cIndex].hasArtifact = true
            store.projects[pIndex].codebases[cIndex].lastIndexed = Date()
            store.projects[pIndex].codebases[cIndex].hasParseErrors = newArtifact.metadata.hasParseErrors
            store.projects[pIndex].codebases[cIndex].parseDiagnosticCount = newArtifact.metadata.parseDiagnostics.count
            if let refreshedBookmark {
                store.projects[pIndex].codebases[cIndex].securityScopedBookmark = refreshedBookmark
            }
            store.saveArtifact(newArtifact, for: codebaseID)
            persistProject(store.projects[pIndex].id)
        } catch {
            store.report("Reindex failed: \(error.localizedDescription)")
        }
    }
}
