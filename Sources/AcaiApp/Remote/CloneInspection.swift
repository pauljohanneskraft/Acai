import AcaiGit
import Foundation

/// What a shared hub clone looks like on disk right now, without touching the remote.
struct CloneInspection: Sendable, Equatable {
    var isCloned: Bool
    var isShallow: Bool
    var lastFetchedAt: Date?
    var worktreeNames: [String]

    static let absent = CloneInspection(isCloned: false, isShallow: false, lastFetchedAt: nil, worktreeNames: [])

    init(isCloned: Bool, isShallow: Bool, lastFetchedAt: Date?, worktreeNames: [String]) {
        self.isCloned = isCloned
        self.isShallow = isShallow
        self.lastFetchedAt = lastFetchedAt
        self.worktreeNames = worktreeNames
    }

    /// Reads libgit2's bookkeeping, so it belongs off the main actor.
    init(hub: GitRepository) {
        guard hub.isCloned else {
            self = .absent
            return
        }
        let names = (try? GitWorktree(repositoryDirectory: hub.localPath).list()) ?? []
        self.init(
            isCloned: true, isShallow: hub.isShallow, lastFetchedAt: hub.lastFetchedAt, worktreeNames: names.sorted())
    }
}
