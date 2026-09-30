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

    /// Blames `path` — relative to the repository root — once and answers every line in `lines`, so
    /// a file carrying many findings costs one walk rather than one per line. A line libgit2 can't
    /// attribute (past the end of the file, or never committed) is absent from the result rather
    /// than guessed at, and an empty `lines` reads nothing at all.
    ///
    /// The whole file is blamed rather than `git_blame_options`' line window: the callers' lines are
    /// scattered through the file, so a window spanning the first to the last saves nothing, and a
    /// window is one more thing to get wrong when a stale index names a line past the file's end.
    ///
    /// Throws `HistoryNotFetched` for a shallow clone, where blame charges every line older than the
    /// graft to the boundary commit — an answer that looks real and isn't.
    public func lines(_ lines: Set<Int>, inFile path: String) throws -> [Int: Line] {
        guard !lines.isEmpty else { return [:] }
        try GitHistoryAvailability(directory: directory).requireFullHistory()

        return try withRepositoryPointer { repositoryPointer in
            var options = git_blame_options()
            guard git_blame_options_init(&options, UInt32(GIT_BLAME_OPTIONS_VERSION)) == 0 else {
                throw Failure.libgit2(Self.lastErrorMessage("Couldn't initialize blame options"))
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
