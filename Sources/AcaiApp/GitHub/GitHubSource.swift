import Foundation

/// Identifies a specific ref of a GitHub repository to clone — `owner`/`repo`/`ref` always travel
/// together, so this exists mainly to keep call sites like `addGitHubCodebase` under the project's
/// function-parameter-count limit rather than taking the three as separate arguments.
struct GitHubRepositoryRef: Hashable {
    var owner: String
    var repo: String
    var ref: String
    var kind: GitHubRef.Kind
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
    /// Whether `ref` names a branch or a tag — for display (the branch/tag picker) and
    /// `GitHubRef.id`'s disambiguation of a repo where a branch and tag share a name.
    var refKind: GitHubRef.Kind
    var lastSyncedCommitSHA: String?
    var lastSyncedAt: Date?

    init(
        owner: String, repo: String, ref: String, refKind: GitHubRef.Kind = .branch,
        lastSyncedCommitSHA: String? = nil, lastSyncedAt: Date? = nil
    ) {
        self.owner = owner
        self.repo = repo
        self.ref = ref
        self.refKind = refKind
        self.lastSyncedCommitSHA = lastSyncedCommitSHA
        self.lastSyncedAt = lastSyncedAt
    }

    enum CodingKeys: String, CodingKey {
        case owner, repo, ref, refKind, lastSyncedCommitSHA, lastSyncedAt
    }

    /// Codebases saved before `refKind` existed have no such key on disk — default those to
    /// `.branch`, the only kind this feature supported at the time.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(String.self, forKey: .owner)
        repo = try container.decode(String.self, forKey: .repo)
        ref = try container.decode(String.self, forKey: .ref)
        refKind = try container.decodeIfPresent(GitHubRef.Kind.self, forKey: .refKind) ?? .branch
        lastSyncedCommitSHA = try container.decodeIfPresent(String.self, forKey: .lastSyncedCommitSHA)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(owner, forKey: .owner)
        try container.encode(repo, forKey: .repo)
        try container.encode(ref, forKey: .ref)
        try container.encode(refKind, forKey: .refKind)
        try container.encodeIfPresent(lastSyncedCommitSHA, forKey: .lastSyncedCommitSHA)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
    }
}
