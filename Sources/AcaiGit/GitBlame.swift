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

    /// Which version of each file the asked-about line numbers belong to.
    public enum Source: Sendable, Equatable {
        /// A branch, tag, SHA or `HEAD~N` chain — for a codebase analysed at a fixed revision, which
        /// must not read the shared clone's HEAD.
        case revision(String)
        /// The files as they are on disk, blamed against HEAD: a line that isn't committed yet
        /// carries no authorship, and every line below it keeps its own.
        case workingTree
    }

    /// The commit that last touched a line.
    public struct Line: Sendable, Hashable {
        public let authorName: String
        /// The committer date — when the change landed on this history, not when it was first written.
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

    /// The most recent change inside each range, so a declaration spanning many lines reports the
    /// latest activity anywhere in it rather than only on its first line.
    ///
    /// Blames each file once, under a single repository handle. A range libgit2 can't attribute
    /// (past the end of the file, or only uncommitted lines) is absent from the result rather than
    /// guessed at, and so is a file it can't read at all — untracked, or renamed out from under a
    /// stale index — rather than that one file failing the rest.
    ///
    /// Throws `HistoryNotFetched` for a shallow clone, where blame charges every line older than the
    /// graft to the boundary commit — an answer that looks real and isn't. Throws
    /// `CancellationError` between files once the calling task is cancelled.
    public func lastTouched(
        inRangesByFile rangesByFile: [String: Set<ClosedRange<Int>>], source: Source
    ) throws -> [String: [ClosedRange<Int>: Line]] {
        let wanted = rangesByFile.filter { !$0.value.isEmpty }
        guard !wanted.isEmpty else { return [:] }
        try GitHistoryAvailability(directory: directory).requireFullHistory()
        // Resolved before the raw handle is opened, so `SwiftGitX.Repository`'s own runtime
        // init/shutdown pair doesn't nest inside `withRepositoryPointer`'s.
        let commit: String? = if case .revision(let ref) = source { try commitSHA(for: ref) } else { nil }

        return try withRepositoryPointer { repositoryPointer in
            var result: [String: [ClosedRange<Int>: Line]] = [:]
            for (path, ranges) in wanted {
                if Task.isCancelled { throw CancellationError() }
                let file = BlamedFile(path: path, repository: repositoryPointer, directory: directory)
                let blamed = try? file.lastTouched(in: ranges, commit: commit)
                guard let blamed, !blamed.isEmpty else { continue }
                result[path] = blamed
            }
            return result
        }
    }

    /// The ref's commit, through the same revision grammar the rest of `AcaiGit` accepts — branch,
    /// tag, SHA or a `HEAD~N` chain — rather than libgit2's own `rev-parse`.
    private func commitSHA(for ref: String) throws -> String {
        let repository = try Repository(at: directory, createIfNotExists: false)
        return try GitReference(name: ref).resolve(in: repository).id.hex
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
            throw Failure(context: "Couldn't open \"\(directory.path)\"")
        }
        defer { git_repository_free(repositoryPointer) }

        return try body(repositoryPointer)
    }
}

extension GitBlame.Failure {
    /// Appends libgit2's own last error message to `context`, when it left one.
    init(context: String) {
        if let error = git_error_last(), let message = error.pointee.message {
            self = .libgit2("\(context): \(String(cString: message))")
        } else {
            self = .libgit2(context)
        }
    }
}

/// One file's blame under an already-open repository handle.
private struct BlamedFile {
    let path: String
    let repository: OpaquePointer
    let directory: URL

    /// A hunk's extent in the blamed version of the file, with its authorship.
    private struct Hunk {
        let lines: ClosedRange<Int>
        let authorship: GitBlame.Line
    }

    /// `commit` names the revision the ranges are numbered in; `nil` numbers them in the working tree.
    func lastTouched(
        in ranges: Set<ClosedRange<Int>>, commit: String?
    ) throws -> [ClosedRange<Int>: GitBlame.Line] {
        let hunks: [Hunk]
        if let commit {
            hunks = try revisionHunks(for: ranges, commit: commit)
        } else {
            hunks = try workingTreeHunks()
        }
        return ranges.reduce(into: [ClosedRange<Int>: GitBlame.Line]()) { result, range in
            let latest = hunks
                .filter { $0.lines.overlaps(range) }
                .max { $0.authorship.changedAt < $1.authorship.changedAt }
            result[range] = latest?.authorship
        }
    }

    /// Blames only the window the ranges span, clamped to the file's length: libgit2 doesn't clamp
    /// `max_line` itself, and a stale index can name a line past the end.
    private func revisionHunks(for ranges: Set<ClosedRange<Int>>, commit: String) throws -> [Hunk] {
        let lineCount = try lineCount(at: commit)
        let clamped = ranges.compactMap { range -> ClosedRange<Int>? in
            let lower = max(range.lowerBound, 1)
            let upper = min(range.upperBound, lineCount)
            return lower <= upper ? lower...upper : nil
        }
        guard let first = clamped.map(\.lowerBound).min(),
            let last = clamped.map(\.upperBound).max() else { return [] }

        var options = try blameOptions()
        var oid = git_oid()
        guard git_oid_fromstr(&oid, commit) == 0 else {
            throw GitBlame.Failure(context: "Couldn't read commit \"\(commit)\"")
        }
        options.newest_commit = oid
        options.min_line = first
        options.max_line = last

        let blame = try blameFile(options: &options)
        defer { git_blame_free(blame) }
        return hunks(of: blame)
    }

    /// Blames HEAD, then lays the file's on-disk contents over it, so line numbers match what was
    /// analysed. The whole file is blamed: the buffer's line numbers aren't HEAD's, so a window
    /// expressed in them would cut the wrong lines.
    private func workingTreeHunks() throws -> [Hunk] {
        let contents = try Data(contentsOf: directory.appendingPathComponent(path))
        guard !contents.isEmpty else { return [] }

        var options = try blameOptions()
        let base = try blameFile(options: &options)
        defer { git_blame_free(base) }

        var overlaid: OpaquePointer?
        let status = contents.withUnsafeBytes { buffer in
            git_blame_buffer(
                &overlaid, base, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), buffer.count)
        }
        guard status == 0, let overlaid else {
            throw GitBlame.Failure(context: "Couldn't blame the working-tree contents of \"\(path)\"")
        }
        defer { git_blame_free(overlaid) }
        return hunks(of: overlaid)
    }

    private func blameOptions() throws -> git_blame_options {
        var options = git_blame_options()
        guard git_blame_options_init(&options, UInt32(GIT_BLAME_OPTIONS_VERSION)) == 0 else {
            throw GitBlame.Failure(context: "Couldn't initialize blame options")
        }
        options.flags |= GIT_BLAME_USE_MAILMAP.rawValue
        return options
    }

    private func blameFile(options: inout git_blame_options) throws -> OpaquePointer {
        var blamePointer: OpaquePointer?
        guard git_blame_file(&blamePointer, repository, path, &options) == 0, let blamePointer else {
            throw GitBlame.Failure(context: "Couldn't blame \"\(path)\"")
        }
        return blamePointer
    }

    /// Hunks libgit2 left unsigned — lines not committed yet — are skipped rather than attributed.
    private func hunks(of blame: OpaquePointer) -> [Hunk] {
        (0..<git_blame_hunkcount(blame)).compactMap { index -> Hunk? in
            guard let hunk = git_blame_hunk_byindex(blame, index)?.pointee,
                hunk.lines_in_hunk > 0,
                let authorship = GitBlame.Line(hunk) else { return nil }
            let start = Int(hunk.final_start_line_number)
            return Hunk(lines: start...(start + Int(hunk.lines_in_hunk) - 1), authorship: authorship)
        }
    }

    /// Counted the way libgit2 counts, so a final line without a newline still counts.
    private func lineCount(at commit: String) throws -> Int {
        var object: OpaquePointer?
        guard git_revparse_single(&object, repository, "\(commit):\(path)") == 0, let object else {
            throw GitBlame.Failure(context: "Couldn't find \"\(path)\" at \(commit)")
        }
        defer { git_object_free(object) }
        let size = Int(git_blob_rawsize(object))
        guard size > 0, let raw = git_blob_rawcontent(object) else { return 0 }
        let bytes = UnsafeRawBufferPointer(start: raw, count: size)
        let newlines = bytes.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
        return bytes.last == UInt8(ascii: "\n") ? newlines : newlines + 1
    }
}

extension GitBlame.Line {
    /// `nil` for a hunk libgit2 left unsigned, rather than an empty author standing in for one.
    init?(_ hunk: git_blame_hunk) {
        guard let author = hunk.final_signature, let name = author.pointee.name,
            let committer = hunk.final_committer else { return nil }
        self.init(
            authorName: String(cString: name),
            changedAt: Date(timeIntervalSince1970: TimeInterval(committer.pointee.when.time)))
    }
}
