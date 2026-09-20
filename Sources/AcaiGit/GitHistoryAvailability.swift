import Foundation
import SwiftGitX
import libgit2

/// Whether a repository carries its complete history or only a shallow cut of it. Read from the
/// common directory's `shallow` file, because `git_repository_is_shallow` reports `false` from a
/// linked worktree of a shallow clone.
public struct GitHistoryAvailability {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var isShallow: Bool {
        guard let root = GitRepositoryRoot(directory: directory).find() else { return false }
        guard (try? SwiftGitXRuntime.initialize()) != nil else { return false }
        defer { _ = try? SwiftGitXRuntime.shutdown() }

        var repositoryPointer: OpaquePointer?
        guard git_repository_open(&repositoryPointer, root.path) == 0, let repositoryPointer else { return false }
        defer { git_repository_free(repositoryPointer) }
        guard let commonDirectory = git_repository_commondir(repositoryPointer) else { return false }

        let shallowFile = URL(fileURLWithPath: String(cString: commonDirectory)).appendingPathComponent("shallow")
        let size = (try? FileManager.default.attributesOfItem(atPath: shallowFile.path)[.size] as? Int) ?? 0
        return size > 0
    }

    /// For operations that walk history and would otherwise stop silently at the shallow boundary.
    public func requireFullHistory() throws {
        if isShallow { throw HistoryNotFetched() }
    }
}

/// History-walking features refuse to answer from a shallow clone rather than presenting a
/// truncated history as the complete one.
public struct HistoryNotFetched: LocalizedError, Equatable {
    public init() {}

    public var errorDescription: String? {
        "Only the latest snapshot of this repository was cloned, so its history isn't available yet. "
        + "Fetch the full history to use this."
    }
}
