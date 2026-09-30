import Foundation
import SwiftGitX
import libgit2

/// Who last changed each line of a file, and when. Calls `git_blame_*` directly, the same direct
/// C-interop arrangement `GitWorktree` uses and for the same reason: `SwiftGitX` has no blame API
/// of its own, while `libgit2` is already linked.
///
/// Kept independent of `GitRepository`'s shared-clone scheme (`GitRepository.blame` delegates to
/// this) so it also works against a plain local working directory found via `GitRepositoryRoot`.
public struct GitBlame: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The commit that last touched one line.
    public struct Line: Sendable, Hashable {
        public let authorName: String
        public let changedAt: Date

        public init(authorName: String, changedAt: Date) {
            self.authorName = authorName
            self.changedAt = changedAt
        }
    }

    public enum Failure: LocalizedError {
        case libgit2(String)

        public var errorDescription: String? {
            switch self {
            case .libgit2(let message):
                message
            }
        }
    }

    /// Blames each file once, under a single repository handle, so a list of findings spread over
    /// many files costs one open and one walk per file rather than one of each per finding. A line
    /// libgit2 can't attribute (past the end of the file, or never committed) is absent from the
    /// result rather than guessed at, and so is a file it can't read at all — untracked, or renamed
    /// out from under a stale index — rather than that one file failing the rest.
    ///
    /// Whole files are blamed rather than `git_blame_options`' line window: a caller's lines are
    /// scattered through the file, so a window spanning the first to the last saves little, and it
    /// is one more thing to get wrong when a stale index names a line past the file's end.
    ///
    /// Blames as of `ref` — a codebase pinned to one revision must not read the shared clone's HEAD,
    /// which belongs to whichever codebase checked it out last. `nil` means the repository's own HEAD.
    ///
    /// Throws `HistoryNotFetched` for a shallow clone, where blame charges every line older than the
    /// graft to the boundary commit — an answer that looks real and isn't.
    public func lines(byFile linesByFile: [String: Set<Int>], ref: String? = nil) throws -> [String: [Int: Line]] {
        let wanted = linesByFile.filter { !$0.value.isEmpty }
        guard !wanted.isEmpty else { return [:] }
        try GitHistoryAvailability(directory: directory).requireFullHistory()
        // Resolved before the raw handle is opened, so `SwiftGitX.Repository`'s own runtime
        // init/shutdown pair doesn't nest inside `withRepositoryPointer`'s.
        let newestCommit = try ref.map { try commitSHA(for: $0) }

        return try withRepositoryPointer { repositoryPointer in
            wanted.reduce(into: [String: [Int: Line]]()) { result, entry in
                let blamed = try? blame(
                    entry.value, inFile: entry.key, newestCommit: newestCommit, in: repositoryPointer)
                guard let blamed, !blamed.isEmpty else { return }
                result[entry.key] = blamed
            }
        }
    }

    /// The ref's commit, through the same revision grammar the rest of `AcaiGit` accepts — branch,
    /// tag, SHA or a `HEAD~N` chain — rather than libgit2's own `rev-parse`.
    private func commitSHA(for ref: String) throws -> String {
        let repository = try Repository(at: directory, createIfNotExists: false)
        return try GitReference(name: ref).resolve(in: repository).id.hex
    }

    private func blame(
        _ lines: Set<Int>, inFile path: String, newestCommit: String?, in repositoryPointer: OpaquePointer
    ) throws -> [Int: Line] {
        var options = git_blame_options()
        guard git_blame_options_init(&options, UInt32(GIT_BLAME_OPTIONS_VERSION)) == 0 else {
            throw Failure.libgit2(Self.lastErrorMessage("Couldn't initialize blame options"))
        }
        if let newestCommit {
            var oid = git_oid()
            guard git_oid_fromstr(&oid, newestCommit) == 0 else {
                throw Failure.libgit2(Self.lastErrorMessage("Couldn't read commit \"\(newestCommit)\""))
            }
            options.newest_commit = oid
        }

        var blamePointer: OpaquePointer?
        guard git_blame_file(&blamePointer, repositoryPointer, path, &options) == 0,
            let blamePointer else {
            throw Failure.libgit2(Self.lastErrorMessage("Couldn't blame \"\(path)\""))
        }
        defer { git_blame_free(blamePointer) }

        return lines.reduce(into: [Int: Line]()) { result, line in
            guard line > 0,
                let hunk = git_blame_hunk_byline(blamePointer, line),
                let blamed = Line(hunk.pointee) else { return }
            result[line] = blamed
        }
    }

    /// Opens `directory` as a raw libgit2 handle and always frees it afterward. Pairs
    /// `SwiftGitXRuntime.initialize()`/`.shutdown()` itself, because bypassing `SwiftGitX.Repository`
    /// also bypasses the global runtime init its `init`/`deinit` pair provides — see
    /// `GitWorktree.withRepositoryPointer`.
    private func withRepositoryPointer<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        do {
            try SwiftGitXRuntime.initialize()
        } catch {
            throw Failure.libgit2("Couldn't initialize libgit2: \(error.message)")
        }
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var repositoryPointer: OpaquePointer?
        guard git_repository_open(&repositoryPointer, directory.path) == 0,
            let repositoryPointer else {
            throw Failure.libgit2(Self.lastErrorMessage("Couldn't open \"\(directory.path)\""))
        }
        defer { git_repository_free(repositoryPointer) }

        return try body(repositoryPointer)
    }

    private static func lastErrorMessage(_ context: String) -> String {
        if let error = git_error_last(), let message = error.pointee.message {
            return "\(context): \(String(cString: message))"
        }
        return context
    }
}

extension GitBlame.Line {
    /// `nil` for a hunk libgit2 left unsigned, rather than an empty author standing in for one.
    init?(_ hunk: git_blame_hunk) {
        guard let signature = hunk.final_signature, let name = signature.pointee.name else { return nil }
        self.init(
            authorName: String(cString: name),
            changedAt: Date(timeIntervalSince1970: TimeInterval(signature.pointee.when.time)))
    }
}
