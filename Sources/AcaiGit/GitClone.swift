import Foundation
import SwiftGitX

/// Clones (or, if `destination` already holds a checkout of the same remote, incrementally
/// fetches and switches) a remote repository at `ref` into `destination` — a real `.git` checkout,
/// replacing a downloaded-and-extracted zipball. `remoteURL` carries any needed credentials
/// embedded in its userinfo component (e.g. `https://x-access-token:{PAT}@github.com/owner/repo.git`
/// — libgit2's HTTP transport authenticates from URL-embedded credentials directly, no separate
/// callback needed); this type has no notion of GitHub or PATs itself.
public struct GitClone {
    public let remoteURL: URL
    public let ref: String

    public init(remoteURL: URL, ref: String) {
        self.remoteURL = remoteURL
        self.ref = ref
    }

    /// Clones/syncs `destination` to `ref`'s current commit, replacing its contents (if any) only
    /// once the whole operation has fully succeeded — a failed sync leaves whatever was there
    /// before untouched. Returns the resolved commit's SHA.
    @discardableResult
    public func sync(into destination: URL) async throws -> String {
        let repository = try await openOrClone(into: destination)
        try GitCheckout(directory: destination, repository: repository).switchTo(ref: ref)

        guard let commit = try repository.HEAD.target as? Commit else {
            throw GitReference.Failure.notFound(ref)
        }
        return commit.id.hex
    }

    private func openOrClone(into destination: URL) async throws -> Repository {
        let gitDir = destination.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            do {
                let repository = try Repository(at: destination, createIfNotExists: false)
                try await repository.fetch()
                return repository
            } catch {
                throw error.asFailure("Couldn't fetch the repository")
            }
        }

        let workDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let scratchClone = workDir.appendingPathComponent("clone", isDirectory: true)

        do {
            _ = try await Repository.clone(from: remoteURL, to: scratchClone)
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
