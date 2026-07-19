import Foundation

/// Identifies a specific ref of a GitHub repository to clone — `owner`/`repo`/`ref` always travel
/// together, so this exists mainly to keep call sites like `addGitHubCodebase` under the project's
/// function-parameter-count limit rather than taking the three as separate arguments.
struct GitHubRepositoryRef: Hashable {
    var owner: String
    var repo: String
    var ref: String
}

/// Marks a `Codebase` as originating from an in-app GitHub clone rather than a user-picked local
/// folder. When present, `Codebase.directoryPath` points at the app-managed clone folder (under
/// `ProjectStore.githubClonesDir`) and `Codebase.securityScopedBookmark` stays `nil` — that folder
/// lives inside the app's own container, so no bookmark is needed on either platform.
struct GitHubSource: Codable, Hashable {
    var owner: String
    var repo: String
    /// A branch or tag name. Switching branches/tags is a resync in place: this is updated and
    /// the clone folder's contents are replaced, rather than modeling multiple refs per codebase
    /// — a user wanting two branches side by side adds two codebases against the same repo.
    var ref: String
    var lastSyncedCommitSHA: String?
    var lastSyncedAt: Date?
}
