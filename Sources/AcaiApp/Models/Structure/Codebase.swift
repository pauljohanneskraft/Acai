import Foundation

struct Codebase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    /// What re-establishes access to `directoryPath` after relaunch under the sandbox. `nil` for an
    /// app-managed directory (see `githubSource`) and for codebases added before this field existed
    /// — those fall back to the plain path, which the sandbox may refuse.
    var securityScopedBookmark: SecurityScopedBookmark?
    /// Set when this codebase was cloned in-app from GitHub rather than pointed at a user-picked
    /// local folder — see `GitHubSource`. When present, `directoryPath` is the app-managed clone
    /// folder and `securityScopedBookmark` stays `nil`.
    var githubSource: GitHubSource?
    var hasArtifact: Bool = false
    var lastIndexed: Date?
    var hasParseErrors: Bool = false
    var parseDiagnosticCount: Int = 0
    var qualityCheck: QualityCheckConfiguration?
    /// Applied at indexing time; `nil` means unfiltered.
    var fileFilter: FileFilter?
    /// Set when this codebase is linked to a shared `GitRepository` — e.g. a local folder that
    /// turned out to already be a git working directory (the transparent upgrade). `directoryPath`
    /// remains the authoritative on-disk location for now; nothing yet re-resolves file access
    /// through this reference.
    var repository: CodebaseRepositoryReference?
}
