import Foundation

extension ProjectStore {
    /// Stable and unique per codebase, so it can't collide with a branch/worktree name a user
    /// might otherwise pick.
    func gitWorktreeName(for codebaseID: UUID) -> String {
        "codebase-\(codebaseID.uuidString)"
    }

    func gitWorktreeURL(for codebaseID: UUID) -> URL {
        gitWorktreesDir.appendingPathComponent(codebaseID.uuidString, isDirectory: true)
    }
}
