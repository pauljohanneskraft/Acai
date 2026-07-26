import Foundation

struct Codebase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    /// On iOS, the security-scoped bookmark minted when the directory was picked via
    /// `.fileImporter`, so access survives relaunch under App Sandbox rules. `nil` on macOS (not
    /// sandboxed — `directoryPath` alone is authoritative there) and for codebases added before
    /// this field existed.
    var securityScopedBookmark: SecurityScopedBookmark?
    /// Set when this codebase was cloned in-app from GitHub rather than pointed at a user-picked
    /// local folder — see `GitHubSource`. When present, `directoryPath` is the app-managed clone
    /// folder and `securityScopedBookmark` stays `nil`.
    var githubSource: GitHubSource?
    var hasArtifact: Bool = false
    var lastIndexed: Date?
    /// `true` when the most recent index encountered files that could not be fully parsed.
    var hasParseErrors: Bool = false
    /// Number of concrete parse problems found during the most recent index.
    var parseDiagnosticCount: Int = 0
    /// The codebase's code-quality check, if set up. `nil` means none exists yet.
    var qualityCheck: QualityCheckConfiguration?
    /// This codebase's file allow/blocklist, applied at indexing time. `nil` means unfiltered.
    var fileFilter: FileFilter?
    /// Set when this codebase is linked to a shared `GitRepository` (see `CodebaseRepositoryReference`)
    /// — e.g. a local folder that turned out to already be a git working directory (B04's transparent
    /// upgrade). `nil` for a codebase that's just a plain directory with no known repository.
    /// `directoryPath` remains the authoritative resolved on-disk location for now; nothing yet
    /// re-resolves file access through this reference — that's a future worktree-integration pass
    /// (B03's app-layer wiring).
    var repository: CodebaseRepositoryReference?
}
