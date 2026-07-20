import Foundation
import SwiftGitX

/// Operates on an already-cloned repository directory: fetch, list refs, switch to a ref, read
/// HEAD — the cross-platform replacement for `GitCommand`/`GitRefs` (which shelled out to
/// `/usr/bin/git` and were `#if os(macOS)`-only).
public struct GitCheckout {
    public let directory: URL
    private let repository: Repository

    public enum Failure: LocalizedError {
        case notAGitRepository(String)

        public var errorDescription: String? {
            switch self {
            case .notAGitRepository(let path):
                "\"\(path)\" is not a git repository."
            }
        }
    }

    /// `directory` may be the repository root or any subdirectory of it (e.g. one package of a
    /// monorepo) — `GitRepositoryRoot` finds the actual root libgit2 needs.
    public init(directory: URL) throws {
        guard let root = GitRepositoryRoot(directory: directory).find() else {
            throw Failure.notAGitRepository(directory.path)
        }
        do {
            self.repository = try Repository(at: root, createIfNotExists: false)
        } catch {
            throw Failure.notAGitRepository(directory.path)
        }
        self.directory = directory
    }

    /// Reuses an already-open repository, e.g. right after `GitClone` opened or cloned it.
    init(directory: URL, repository: Repository) {
        self.directory = directory
        self.repository = repository
    }

    /// Fetches the `origin` remote's objects and refs — incremental, not a full re-download.
    public func fetch() async throws {
        do {
            try await repository.fetch()
        } catch {
            throw error.asFailure("Couldn't fetch the repository")
        }
    }

    /// Local branch names merged with remote branch names (their `origin/`-style prefix
    /// stripped), then tag names — each alphabetical. Mirrors the old `GitRefs.names()` shape.
    public func refNames() throws -> [String] {
        let localBranches: [Branch]
        let remoteBranches: [Branch]
        let tags: [Tag]
        do {
            localBranches = try repository.branch.list(.local)
            remoteBranches = try repository.branch.list(.remote)
            tags = try repository.tag.list()
        } catch {
            throw error.asFailure("Couldn't list branches and tags")
        }

        var branchNames = Set<String>()
        for branch in localBranches {
            branchNames.insert(branch.name)
        }
        for branch in remoteBranches {
            let parts = branch.name.split(separator: "/", maxSplits: 1)
            branchNames.insert(parts.count == 2 ? String(parts[1]) : branch.name)
        }

        return branchNames.sorted() + tags.map(\.name).sorted()
    }

    /// The repository's current HEAD commit SHA.
    public var headCommitSHA: String {
        get throws {
            guard let commit = try repository.HEAD.target as? Commit else {
                throw Failure.notAGitRepository(directory.path)
            }
            return commit.id.hex
        }
    }

    /// Switches the working directory to `ref`. Prefers an actual branch or tag switch (which
    /// attaches HEAD to that branch/tag, so a later `fetch` still knows what to track); falls back
    /// to `GitReference`'s resolver — and a detached HEAD — for an arbitrary revision (a SHA,
    /// `HEAD~3`, …).
    public func switchTo(ref: String) throws {
        do {
            if let branch = repository.branch["origin/\(ref)", type: .remote] ?? repository.branch[ref, type: .local] {
                try repository.switch(to: branch)
            } else if let tag = repository.tag[ref] {
                try repository.switch(to: tag)
            } else {
                let commit = try GitReference(name: ref).resolve(in: repository)
                try repository.switch(to: commit)
            }
        } catch let error as SwiftGitXError {
            throw error.asFailure("Couldn't switch to \"\(ref)\"")
        } catch {
            throw error
        }
    }
}
