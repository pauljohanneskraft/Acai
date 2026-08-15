import Foundation
import SwiftGitX
import libgit2

/// Operates on an already-cloned repository directory: fetch, list refs, switch to a ref, read
/// HEAD. Cross-platform replacement for shelling out to `/usr/bin/git`.
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

    /// Incremental fetch of the `origin` remote — not a full re-download. Reports transfer
    /// progress through `onProgress` and aborts cooperatively if the calling `Task` is cancelled —
    /// see `GitFetch`.
    public func fetch(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await GitFetch(repositoryDirectory: directory).run(onProgress: onProgress)
    }

    /// A branch or tag name paired with its kind.
    public struct Ref: Identifiable, Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            case branch
            case tag
        }

        public var name: String
        public var kind: Kind
        public var id: String { "\(kind.rawValue)-\(name)" }
    }

    /// Local and remote branch refs merged (remote's `origin/`-style prefix stripped), then tags —
    /// each alphabetical within its kind.
    public func refs() throws -> [Ref] {
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

        return branchNames.sorted().map { Ref(name: $0, kind: .branch) }
            + tags.map(\.name).sorted().map { Ref(name: $0, kind: .tag) }
    }

    /// Names only, for callers that don't need kinds.
    public func refNames() throws -> [String] {
        try refs().map(\.name)
    }

    public var headCommitSHA: String {
        get throws {
            guard let commit = try repository.HEAD.target as? Commit else {
                throw Failure.notAGitRepository(directory.path)
            }
            return commit.id.hex
        }
    }

    /// The `origin` remote's URL, or `nil` if this repository has no such remote configured (e.g.
    /// a purely local repository with no remote at all).
    public var originRemoteURL: URL? {
        repository.remote["origin"]?.url
    }

    /// The current ref in whatever form best identifies it for a later `switchTo(ref:)`/
    /// `GitRepository.sync(ref:)` call: the branch name if HEAD is attached to one, otherwise the
    /// current commit's full SHA (a SHA round-trips through `GitReference` just as well as a tag
    /// name, so a detached-at-a-tag HEAD doesn't need special-casing here).
    public var currentRef: String {
        get throws {
            do {
                if repository.isHEADDetached {
                    guard let commit = try repository.HEAD.target as? Commit else {
                        throw Failure.notAGitRepository(directory.path)
                    }
                    return commit.id.hex
                }
                return try repository.HEAD.name
            } catch let error as SwiftGitXError {
                throw error.asFailure("Couldn't determine the current ref")
            } catch {
                throw error
            }
        }
    }

    /// The most recent commit both `a` and `b` share as an ancestor — three-dot diff semantics (e.g.
    /// a pull request's base branch vs. its head, not the base branch's own tip). `SwiftGitX`
    /// exposes no merge-base primitive, so this opens its own raw libgit2 handle for `directory`'s
    /// repository root and calls `git_merge_base` directly, following `GitWorktree`'s precedent for
    /// bypassing `SwiftGitX.Repository` (and pairing `SwiftGitXRuntime.initialize()`/`.shutdown()`
    /// the same way, since that init/shutdown pair only happens as a side effect of a live
    /// `SwiftGitX.Repository`, which this deliberately never opens).
    public func mergeBase(_ a: String, _ b: String) throws -> String {
        guard let root = GitRepositoryRoot(directory: directory).find() else {
            throw Failure.notAGitRepository(directory.path)
        }

        func message(_ context: String) -> String {
            if let error = git_error_last(), let text = error.pointee.message {
                return "\(context): \(String(cString: text))"
            }
            return context
        }

        do {
            try SwiftGitXRuntime.initialize()
        } catch {
            throw GitFailure(message: "Couldn't initialize libgit2: \(error.message)")
        }
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var repositoryPointer: OpaquePointer?
        guard git_repository_open(&repositoryPointer, root.path) == 0, let repositoryPointer else {
            throw GitFailure(message: message("Couldn't open \"\(root.path)\""))
        }
        defer { git_repository_free(repositoryPointer) }

        // `git_revparse_single`'s own DWIM search (branch/tag/SHA/`HEAD~N`) never tries an
        // `origin/`-prefixed name, so a branch that only exists as a remote-tracking ref in a clone
        // or linked worktree (e.g. a GitHub-backed codebase's non-default branch) wouldn't resolve
        // by its plain name alone. Try the remote-tracking form first, exactly the priority
        // `GitReference.resolveBase` already established for every other revision lookup in this
        // module, then fall back to `revision` as given (DWIM covers a local branch, tag, SHA, or
        // `HEAD`/`HEAD~N` from there).
        func resolvedOID(for revision: String) throws -> git_oid {
            if let oid = revparsedOID(for: "origin/\(revision)", in: repositoryPointer) {
                return oid
            }
            guard let oid = revparsedOID(for: revision, in: repositoryPointer) else {
                throw GitFailure(message: message("Couldn't resolve \"\(revision)\""))
            }
            return oid
        }

        func revparsedOID(for revision: String, in repositoryPointer: OpaquePointer) -> git_oid? {
            var object: OpaquePointer?
            guard git_revparse_single(&object, repositoryPointer, revision) == 0, let object else { return nil }
            defer { git_object_free(object) }
            return git_object_id(object)?.pointee
        }

        var oidA = try resolvedOID(for: a)
        var oidB = try resolvedOID(for: b)

        var result = git_oid()
        guard git_merge_base(&result, repositoryPointer, &oidA, &oidB) == 0 else {
            throw GitFailure(message: message("Couldn't find a merge base for \"\(a)\" and \"\(b)\""))
        }

        guard let hex = git_oid_tostr_s(&result) else {
            throw GitFailure(message: "Couldn't format the merge-base commit id")
        }
        return String(cString: hex)
    }

    /// Switches to `ref`. Prefers a branch/tag switch (attaches HEAD so a later `fetch` still knows
    /// what to track); falls back to `GitReference`'s resolver with a detached HEAD for an
    /// arbitrary revision (a SHA, `HEAD~3`, …).
    ///
    /// Only safe for a repository's sole checkout. A given branch can only be attached as HEAD in
    /// one checkout at a time (libgit2 rejects a second attempt with "already checked out") — this
    /// is exactly the case for a `GitWorktree`, where the shared clone's own working directory and
    /// every other linked worktree are all separate checkouts of the same repository. Worktree
    /// callers must use `switchToDetached(ref:)` instead.
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

    /// Switches to `ref`'s resolved commit with an always-detached HEAD, whether `ref` names a
    /// branch, a tag, or an arbitrary revision. Unlike `switchTo(ref:)`, this never attaches to a
    /// branch ref, so it never conflicts with that same branch being checked out anywhere else —
    /// the property a `GitWorktree` checkout needs, since its shared repository's own working
    /// directory (and any other linked worktree) may already have that branch attached.
    public func switchToDetached(ref: String) throws {
        do {
            let commit = try GitReference(name: ref).resolve(in: repository)
            try repository.switch(to: commit)
        } catch let error as SwiftGitXError {
            throw error.asFailure("Couldn't switch to \"\(ref)\"")
        } catch {
            throw error
        }
    }
}
