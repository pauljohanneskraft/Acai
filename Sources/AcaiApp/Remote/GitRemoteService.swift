import AcaiGit
import CryptoKit
import Foundation

struct RemoteCheckoutTarget: Sendable {
    var endpoint: RemoteEndpoint
    var ref: String
    var depth: GitHistoryDepth = .full
}

struct GitWorktreeDestination: Sendable {
    /// One subdirectory per remote — see `ProjectStore.gitRepositoriesDir`.
    var hubStoreDirectory: URL
    /// Unused by `resyncWorktree`, which moves an already-registered worktree rather than
    /// creating one.
    var worktreeName: String
    var worktreeDirectory: URL
    /// Serializes fetch-vs-checkout against the shared hub clone across every codebase referencing
    /// it — see `ProjectStore.gitRepositoryLocks`.
    var locks: GitRepositoryLocks
}

/// The git operations a managed codebase needs against any remote, whoever hosts it. Split out so a
/// UI test process can swap in a deterministic, network-free conformance.
protocol GitRemoteService: Sendable {
    /// Branches, tags and the default branch, without cloning.
    func listRemote(_ endpoint: RemoteEndpoint) async throws -> GitRemoteListing.Result

    /// Ensures a shared hub clone exists for the remote (cloning it at `target.depth` if this is
    /// the first codebase to reference it) and registers a brand-new linked worktree. Returns the
    /// checked-out commit and the credential-free remote URL to persist.
    @discardableResult
    func attachWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (headSHA: String, remoteURL: URL)

    /// Fetches the shared hub clone and moves an already-registered worktree to `target.ref`.
    @discardableResult
    func resyncWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> String

    /// The hub's branches and tags as of its last fetch.
    func refs(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async throws -> [GitCheckout.Ref]

    /// Deepens a shallow hub clone to its complete history.
    func fetchFullHistory(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws
}

struct LiveGitRemoteService: GitRemoteService {
    func listRemote(_ endpoint: RemoteEndpoint) async throws -> GitRemoteListing.Result {
        try await GitRemoteListing(remoteURL: endpoint.transportURL).list()
    }

    @discardableResult
    func attachWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (headSHA: String, remoteURL: URL) {
        let headSHA = try await GitWorktreeSync(
            transportURL: target.endpoint.transportURL, ref: target.ref,
            hubStoreDirectory: destination.hubStoreDirectory, locks: destination.locks
        ).attachWorktree(
            named: destination.worktreeName, at: destination.worktreeDirectory, depth: target.depth,
            onProgress: onProgress)
        return (headSHA, target.endpoint.remoteURL)
    }

    @discardableResult
    func resyncWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try await GitWorktreeSync(
            transportURL: target.endpoint.transportURL, ref: target.ref,
            hubStoreDirectory: destination.hubStoreDirectory, locks: destination.locks
        ).resyncWorktree(at: destination.worktreeDirectory, onProgress: onProgress)
    }

    func refs(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async throws -> [GitCheckout.Ref] {
        let hub = GitRepository(remoteURL: endpoint.remoteURL, storeDirectory: hubStoreDirectory)
        return try await Task.detached(priority: .userInitiated) { try hub.refs() }.value
    }

    func fetchFullHistory(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let hub = GitRepository(remoteURL: endpoint.transportURL, storeDirectory: hubStoreDirectory)
        try await locks.run(for: hub) {
            try await hub.fetch(depth: .unshallow, onProgress: onProgress)
        }
    }
}

/// Real libgit2 against a local repository staged by the UI test. A GitHub address is redirected
/// to that fixture remote; any other address (a journey typing the fixture's own path into Remote
/// URL) is used as given. libgit2's local transport can't fetch shallowly, so a latest-snapshot
/// clone is a full clone whose `shallow` file then cuts history at the tip — the same on-disk state
/// a real shallow clone leaves.
struct FixtureGitRemoteService: GitRemoteService {
    let fixtureRemoteURL: URL?

    enum Failure: LocalizedError {
        case noFixtureRemoteConfigured

        var errorDescription: String? {
            "No fixture remote configured for this UI test launch — set "
            + "\(UITestFixtureResolver.gitHubRemoteVariable) if this journey needs to clone."
        }
    }

    private func resolved(_ endpoint: RemoteEndpoint) throws -> URL {
        guard case .github = endpoint.host else { return endpoint.transportURL }
        guard let fixtureRemoteURL else { throw Failure.noFixtureRemoteConfigured }
        return fixtureRemoteURL
    }

    func listRemote(_ endpoint: RemoteEndpoint) async throws -> GitRemoteListing.Result {
        try await GitRemoteListing(remoteURL: try resolved(endpoint)).list()
    }

    @discardableResult
    func attachWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (headSHA: String, remoteURL: URL) {
        let remoteURL = try resolved(target.endpoint)
        let sync = GitWorktreeSync(
            transportURL: remoteURL, ref: target.ref, hubStoreDirectory: destination.hubStoreDirectory,
            locks: destination.locks)
        let wasCloned = sync.hub.isCloned
        let headSHA = try await sync.attachWorktree(
            named: destination.worktreeName, at: destination.worktreeDirectory, onProgress: onProgress)
        if target.depth == .latestSnapshot, !wasCloned {
            let shallowFile = sync.hub.localPath.appendingPathComponent(".git/shallow")
            try Data((headSHA + "\n").utf8).write(to: shallowFile, options: .atomic)
        }
        return (headSHA, remoteURL)
    }

    @discardableResult
    func resyncWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try await GitWorktreeSync(
            transportURL: try resolved(target.endpoint), ref: target.ref,
            hubStoreDirectory: destination.hubStoreDirectory, locks: destination.locks
        ).resyncWorktree(at: destination.worktreeDirectory, onProgress: onProgress)
    }

    func refs(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async throws -> [GitCheckout.Ref] {
        try GitRepository(remoteURL: endpoint.remoteURL, storeDirectory: hubStoreDirectory).refs()
    }

    func fetchFullHistory(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let hub = GitRepository(remoteURL: endpoint.remoteURL, storeDirectory: hubStoreDirectory)
        try await locks.run(for: hub) {
            try? FileManager.default.removeItem(at: hub.localPath.appendingPathComponent(".git/shallow"))
            try await hub.fetch(onProgress: onProgress)
        }
    }
}

/// Network-free *and* git-free: copies an already-staged directory per ref instead of running
/// libgit2, so a journey that just needs a managed codebase to exist doesn't pay for git timing.
struct FastFixtureGitRemoteService: GitRemoteService {
    let sourceDirectoriesByRef: [String: URL]

    enum Failure: LocalizedError {
        case noStagedContent(ref: String)

        var errorDescription: String? {
            switch self {
            case .noStagedContent(let ref):
                "No staged fixture content for ref “\(ref)” — pass it to "
                + "GitFixtureRepository.makeCannedRemote(refs:)."
            }
        }
    }

    private var stagedRefs: [GitCheckout.Ref] {
        sourceDirectoriesByRef.keys.sorted().map { GitCheckout.Ref(name: $0, kind: .branch) }
    }

    func listRemote(_ endpoint: RemoteEndpoint) async throws -> GitRemoteListing.Result {
        GitRemoteListing.Result(refs: stagedRefs, defaultBranch: stagedRefs.first?.name)
    }

    /// Not a real git SHA — nothing downstream validates the format, so a stable per-ref digest is
    /// enough.
    private func cannedSHA(for ref: String) -> String {
        SHA256.hash(data: Data(ref.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func copyStagedTree(for ref: String, to destination: URL) throws {
        guard let source = sourceDirectoriesByRef[ref] else { throw Failure.noStagedContent(ref: ref) }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    @discardableResult
    func attachWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (headSHA: String, remoteURL: URL) {
        try copyStagedTree(for: target.ref, to: destination.worktreeDirectory)
        onProgress?(1)
        return (cannedSHA(for: target.ref), target.endpoint.remoteURL)
    }

    @discardableResult
    func resyncWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try copyStagedTree(for: target.ref, to: destination.worktreeDirectory)
        onProgress?(1)
        return cannedSHA(for: target.ref)
    }

    func refs(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async throws -> [GitCheckout.Ref] {
        stagedRefs
    }

    func fetchFullHistory(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {}
}

struct GitRemoteServiceResolver {
    func resolve() -> GitRemoteService {
        let fixtures = UITestFixtureResolver()
        guard fixtures.resolveBaseDir() != nil else { return LiveGitRemoteService() }
        if let fastFixtureRoot = fixtures.resolveGitHubFastFixtureRoot() {
            let refDirectories = (try? FileManager.default.contentsOfDirectory(
                at: fastFixtureRoot, includingPropertiesForKeys: nil
            )) ?? []
            return FastFixtureGitRemoteService(sourceDirectoriesByRef: Dictionary(
                uniqueKeysWithValues: refDirectories.map { ($0.lastPathComponent, $0) }))
        }
        return FixtureGitRemoteService(fixtureRemoteURL: fixtures.resolveGitHubRemoteURL())
    }
}
