import CryptoKit
import Foundation
import SwiftGitX

/// One shared, on-disk git clone for a remote URL, reused across every `Codebase` that points at
/// it instead of each getting its own independent full clone (today's `GitClone.sync(into:)`
/// model — still used directly by callers that want a single standalone checkout, e.g.
/// `GitHubRepositoryClone`). Reuses `GitClone`'s clone-or-fetch primitive, but pins the destination
/// to a path derived deterministically from `remoteURL` under `storeDirectory`, so two `Codebase`s
/// naming the same remote resolve to the same on-disk clone.
///
/// Named `GitRepository`, not `Repository`: `SwiftGitX` already exports a public `Repository`
/// class that this file (and every other file in this module) imports and uses directly —
/// reusing that name here would silently shadow it for this module's own source files.
public struct GitRepository: Sendable {
    public let remoteURL: URL
    /// The directory under which every shared clone lives, one subdirectory per repository — e.g.
    /// `Application Support/git-repositories`. Callers own choosing this location (an app-container
    /// path, a test's scratch directory, …); `GitRepository` only owns the naming scheme beneath it.
    public let storeDirectory: URL

    public init(remoteURL: URL, storeDirectory: URL) {
        self.remoteURL = remoteURL
        self.storeDirectory = storeDirectory
    }

    /// Where this repository's shared clone lives on disk. Deterministic and collision-resistant:
    /// a SHA-256 digest of the remote URL with any embedded credentials stripped first (a GitHub
    /// PAT is often embedded in `remoteURL`'s userinfo — see
    /// `GitHubRepositoryClone.authenticatedRemoteURL` — and must never end up as part of a
    /// directory name on disk).
    public var localPath: URL {
        storeDirectory.appendingPathComponent(Self.storeKey(for: remoteURL), isDirectory: true)
    }

    /// Clones (if `localPath` doesn't exist yet) or fetches-and-switches (if already cloned) to
    /// `ref`'s current commit. Returns the resolved commit's SHA. This moves the shared clone's own
    /// working directory — callers that want an independent checkout at a different ref
    /// simultaneously should add a `GitWorktree` instead of calling this repeatedly with different
    /// refs.
    @discardableResult
    public func sync(ref: String, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        // `GitClone.sync(into:)` stages a fresh clone in a sibling `.itemReplacementDirectory`
        // before moving it into place — `FileManager` needs `storeDirectory` to already exist to
        // pick an appropriate (same-volume) location for that staging directory, so this can't be
        // left for `GitClone` itself to create only once it's ready to move the finished clone in.
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        return try await GitClone(remoteURL: remoteURL, ref: ref).sync(into: localPath, onProgress: onProgress)
    }

    /// Incremental fetch of the shared clone's `origin` remote, without switching its own ref.
    /// Reports transfer progress through `onProgress` and aborts cooperatively if the calling
    /// `Task` is cancelled — see `GitFetch`.
    public func fetch(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await GitCheckout(directory: localPath).fetch(onProgress: onProgress)
    }

    /// Whether this repository's shared clone has been synced/fetched to disk at least once.
    public var isCloned: Bool {
        FileManager.default.fileExists(atPath: localPath.appendingPathComponent(".git").path)
    }

    /// When the shared clone's `origin` remote was last fetched, or `nil` if it has never been
    /// cloned/fetched. libgit2 (like plain `git`) writes `.git/FETCH_HEAD` on every fetch (and the
    /// initial clone), so its modification date is a reliable "last fetched" signal without this
    /// needing any separate persisted bookkeeping.
    public var lastFetchedAt: Date? {
        let fetchHead = localPath.appendingPathComponent(".git/FETCH_HEAD")
        return try? FileManager.default.attributesOfItem(atPath: fetchHead.path)[.modificationDate] as? Date
    }

    /// Recursive on-disk size of the shared clone (its full `.git` object store plus working
    /// directory), or `nil` if it hasn't been cloned yet.
    public var onDiskSize: Int64? {
        guard isCloned else { return nil }
        return try? DirectoryTreeSize(directory: localPath).compute()
    }

    /// Local and remote branches, then tags — see `GitCheckout.refs()`.
    public func refs() throws -> [GitCheckout.Ref] {
        try GitCheckout(directory: localPath).refs()
    }

    /// The merge-base commit of `a` and `b` — see `GitCheckout.mergeBase(_:_:)`.
    public func mergeBase(_ a: String, _ b: String) throws -> String {
        try GitCheckout(directory: localPath).mergeBase(a, b)
    }

    /// Extracts `ref`'s tree (optionally scoped to `subpath`, e.g. one package of a monorepo) into
    /// a fresh temporary directory. Read-only: never touches the shared clone's own working
    /// directory, HEAD, or index — see `GitDiffSnapshot`.
    public func resolve(subpath: String?, ref: String) throws -> URL {
        let directory = subpath.map { localPath.appendingPathComponent($0, isDirectory: true) } ?? localPath
        return try GitDiffSnapshot(directory: directory, reference: ref).extractedDirectory()
    }

    /// Walks `ref`'s first-parent history, most recent first, up to `limit` commits.
    public func commitHistory(ref: String, limit: Int = 50) throws -> [GitCommitSummary] {
        let repository = try Repository(at: localPath, createIfNotExists: false)
        var commit = try GitReference(name: ref).resolve(in: repository)

        var history: [GitCommitSummary] = []
        history.reserveCapacity(limit)
        while history.count < limit {
            history.append(GitCommitSummary(
                sha: commit.id.hex, summary: commit.summary, authorName: commit.author.name, date: commit.date))
            guard let parent = try commit.parents.first else { break }
            commit = parent
        }
        return history
    }

    /// Aggregates per-file touch counts across `ref`'s first-parent history — the churn half of the
    /// churn × complexity "hotspot" technique. The walk itself lives in `GitChurn` (reused
    /// as-is against any repository directory, not only a shared clone's); this just points it at
    /// the shared clone's own `localPath`.
    public func churnByFile(ref: String, limit: Int = 50) throws -> [String: Int] {
        try GitChurn(directory: localPath).byFile(ref: ref, limit: limit)
    }

    /// A stable, filesystem-safe, credential-free directory name for `remoteURL`: normalizes away
    /// userinfo, host case, and a trailing `.git`, then hashes the result so nothing from the
    /// original URL (including any embedded token) is recoverable from the path on disk.
    private static func storeKey(for remoteURL: URL) -> String {
        var normalized = URLComponents()
        normalized.scheme = remoteURL.scheme
        normalized.host = remoteURL.host?.lowercased()
        normalized.port = remoteURL.port
        normalized.path = remoteURL.path.hasSuffix(".git") ? String(remoteURL.path.dropLast(4)) : remoteURL.path

        let digest = SHA256.hash(data: Data((normalized.string ?? remoteURL.absoluteString).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// One commit's worth of `GitRepository.commitHistory(ref:limit:)` output.
public struct GitCommitSummary: Hashable, Sendable {
    public let sha: String
    public let summary: String
    public let authorName: String
    public let date: Date
}
