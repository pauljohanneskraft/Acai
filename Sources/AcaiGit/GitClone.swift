import Foundation
import SwiftGitX

/// Clones a remote repository at `ref` into `destination`, or — if already checked out there —
/// incrementally fetches and switches instead. `remoteURL` carries any credentials embedded in its
/// userinfo (e.g. `https://x-access-token:{PAT}@github.com/owner/repo.git`); libgit2's HTTP
/// transport authenticates directly from that, no separate callback needed.
public struct GitClone {
    public let remoteURL: URL
    public let ref: String

    public init(remoteURL: URL, ref: String) {
        self.remoteURL = remoteURL
        self.ref = ref
    }

    /// Clones/syncs `destination` to `ref`'s current commit, replacing its contents (if any) only
    /// once the whole operation has fully succeeded — a failed sync leaves whatever was there
    /// before untouched. Returns the resolved commit's SHA. Reports transfer progress through
    /// `onProgress` and aborts cooperatively if the calling `Task` is cancelled — for a fresh
    /// clone, `SwiftGitX`'s own `Repository.clone(from:to:options:transferProgressHandler:)`
    /// already wires both; for an existing checkout, `GitCheckout.fetch(onProgress:)` does (see
    /// `GitFetch`).
    @discardableResult
    public func sync(into destination: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let repository = try await openOrClone(into: destination, onProgress: onProgress)
        try GitCheckout(directory: destination, repository: repository).switchTo(ref: ref)

        guard let commit = try repository.HEAD.target as? Commit else {
            throw GitReference.Failure.notFound(ref)
        }
        return commit.id.hex
    }

    private func openOrClone(
        into destination: URL, onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> Repository {
        let gitDir = destination.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            let repository: Repository
            do {
                repository = try Repository(at: destination, createIfNotExists: false)
            } catch {
                throw error.asFailure("Couldn't open the repository")
            }
            try await GitCheckout(directory: destination, repository: repository).fetch(onProgress: onProgress)
            return repository
        }

        let workDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let scratchClone = workDir.appendingPathComponent("clone", isDirectory: true)

        do {
            _ = try await Repository.clone(
                from: remoteURL, to: scratchClone,
                transferProgressHandler: onProgress.map { onProgress in
                    { (progress: TransferProgress) in
                        guard progress.totalObjects > 0 else { return }
                        onProgress(Double(progress.receivedObjects) / Double(progress.totalObjects))
                    }
                }
            )
        } catch {
            throw error.asFailure("Couldn't clone the repository")
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: scratchClone, to: destination)

        do {
            return try Repository(at: destination, createIfNotExists: false)
        } catch {
            throw error.asFailure("Couldn't open the cloned repository")
        }
    }
}
