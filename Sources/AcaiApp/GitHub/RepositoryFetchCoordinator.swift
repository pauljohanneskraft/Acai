import AcaiGit
import Foundation

/// Fetches each *unique* remote referenced by a batch of codebases at most once, instead of every
/// codebase in a monorepo (N codebases sharing one shared hub clone — see `GitWorktreeSync`)
/// running its own full fetch back-to-back. Sits in front of any "refresh several codebases at
/// once" entry point — today that's `FileWatchReindexCoordinator` (4c) and
/// `ScheduledRefreshCoordinator` (4d), the two triggers that can plausibly touch a monorepo's
/// several codebases in the same pass.
///
/// A remote that was already fetched within `recencyWindow` — by this coordinator, by a manual
/// per-codebase `pull`, or by anything else touching the same shared clone — is skipped, mirroring
/// `pull(codebaseID:)`'s own `latestSHA != lastSyncedCommitSHA` skip-if-unchanged idea one level
/// earlier (before any per-codebase ref resolution even runs).
struct RepositoryFetchCoordinator {
    var recencyWindow: TimeInterval
    private let fetch: @Sendable (GitRepository, (@Sendable (Double) -> Void)?) async throws -> Void

    /// Real fetches, serialized per-repository through `locks` — the production configuration.
    init(locks: GitRepositoryLocks, recencyWindow: TimeInterval = 60) {
        self.recencyWindow = recencyWindow
        self.fetch = { repository, onProgress in
            try await locks.run(for: repository) {
                try await repository.fetch(onProgress: onProgress)
            }
        }
    }

    /// Test seam: swap in a spy instead of a real `GitRepositoryLocks`-serialized fetch.
    init(
        recencyWindow: TimeInterval = 60,
        fetch: @escaping @Sendable (GitRepository, (@Sendable (Double) -> Void)?) async throws -> Void
    ) {
        self.recencyWindow = recencyWindow
        self.fetch = fetch
    }

    /// Fetches each distinct repository in `repositories` (deduped by shared on-disk clone path,
    /// so two `GitRepository` values for the same remote count as one) at most once.
    func fetchEachRemoteOnce(
        among repositories: [GitRepository], onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        var fetchedPaths = Set<String>()
        for repository in repositories {
            guard fetchedPaths.insert(repository.localPath.path).inserted else { continue }
            if let lastFetchedAt = repository.lastFetchedAt,
                Date().timeIntervalSince(lastFetchedAt) < recencyWindow {
                continue
            }
            try await fetch(repository, onProgress)
        }
    }

    /// Same as `fetchEachRemoteOnce(among:onProgress:)`, but derives the repository set from
    /// `codebases`' own worktree-backed `repository` references (`Codebase.repository?.remoteURL`)
    /// — codebases with no such reference (a plain local folder, or an older independent GitHub
    /// clone predating worktree support) have nothing shared to dedup and are skipped.
    func fetchEachRemoteOnce(
        for codebases: [Codebase], hubStoreDirectory: URL, onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let repositories = codebases.compactMap(\.repository?.remoteURL)
            .map { GitRepository(remoteURL: $0, storeDirectory: hubStoreDirectory) }
        try await fetchEachRemoteOnce(among: repositories, onProgress: onProgress)
    }
}
