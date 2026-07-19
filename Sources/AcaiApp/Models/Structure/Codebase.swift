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
    /// The codebase's code-quality check, if one has been set up. `nil` means no check exists yet.
    /// The configuration is just a path to a YAML rules file — either one the app manages internally
    /// (UI-authored rules) or an external file the user pointed at.
    var qualityCheck: QualityCheckConfiguration?
}
