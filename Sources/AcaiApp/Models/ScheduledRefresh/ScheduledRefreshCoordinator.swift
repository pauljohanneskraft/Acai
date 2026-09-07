import AcaiGit
import Foundation

/// Periodically checks each tracked GitHub-backed codebase's remote for a moved `HEAD` and, only
/// when it has, runs a full reindex — by calling the same `pull` closure a manual pull-button tap
/// uses (`ProjectCodebaseEditor.pull(codebaseID:)`), so this coordinator only needs to decide *when*
/// to check, never re-derive *whether* anything changed: `pull`'s own `latestSHA !=
/// lastSyncedCommitSHA` comparison already skips the reindex when the fetch found nothing new.
/// Incremental reindexing is out of scope — a triggered reindex is always the existing full
/// `reindex(codebaseID:)` `pull` itself calls, never a partial re-parse.
///
/// Before `pull`ing several codebases, routes them through `RepositoryFetchCoordinator` (4b) so a
/// monorepo's several codebases sharing one remote fetch it once rather than each running its own —
/// see `sweepOnce()`. `refreshNext()` is the separate one-codebase-at-a-time seam
/// `ScheduledRefreshTaskRunner` drives from a `BGAppRefreshTask` on iOS, where a single background
/// wake can't afford to sweep every codebase.
@MainActor
final class ScheduledRefreshCoordinator {
    private let store: ProjectStore
    private let pull: @Sendable (UUID) async -> Void
    private let fetchCoordinator: RepositoryFetchCoordinator
    private var sweepTask: Task<Void, Never>?
    /// Round-robin position for `refreshNext()`, into `githubBackedCodebaseIDs`'s current order.
    private var cursor = 0

    init(store: ProjectStore, pull: @escaping @Sendable (UUID) async -> Void) {
        self.store = store
        self.pull = pull
        self.fetchCoordinator = RepositoryFetchCoordinator(locks: store.gitRepositoryLocks)
    }

    /// Every GitHub-backed codebase's id, in a stable (declaration) order.
    var githubBackedCodebaseIDs: [UUID] {
        store.projects.flatMap(\.codebases).filter { $0.githubSource != nil }.map(\.id)
    }

    /// macOS: starts a periodic sweep of every GitHub-backed codebase, first deduping the fetch
    /// across codebases that share a remote. Safe to call again — replaces any previously running
    /// sweep rather than stacking a second one.
    func startPeriodicSweep(interval: Duration) {
        sweepTask?.cancel()
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sweepOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPeriodicSweep() {
        sweepTask?.cancel()
        sweepTask = nil
    }

    func sweepOnce() async {
        let codebases = store.projects.flatMap(\.codebases)
        try? await fetchCoordinator.fetchEachRemoteOnce(for: codebases, hubStoreDirectory: store.gitRepositoriesDir)
        for id in githubBackedCodebaseIDs {
            await pull(id)
        }
    }

    /// iOS: pulls exactly one GitHub-backed codebase (the next one in round-robin order) and
    /// reports whether others remain for a follow-up wake to continue. A no-op (returns `false`)
    /// when there are no GitHub-backed codebases at all.
    @discardableResult
    func refreshNext() async -> Bool {
        let ids = githubBackedCodebaseIDs
        guard !ids.isEmpty else { return false }
        if cursor >= ids.count { cursor = 0 }
        let id = ids[cursor]
        cursor += 1
        await pull(id)
        return cursor < ids.count
    }
}
