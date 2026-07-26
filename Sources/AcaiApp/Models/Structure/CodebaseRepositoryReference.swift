import Foundation

/// Records which shared git repository (`AcaiGit`'s `GitRepository`) a `Codebase`'s content is
/// drawn from, and at what ref/subpath — added by B02 so a later pass can resolve a codebase's
/// files through a shared/worktree-based clone instead of only `Codebase.directoryPath`.
///
/// Distinct from `GitHubSource`: `GitHubSource` records how the codebase's *folder* came to exist
/// (an in-app GitHub clone into an app-managed directory); `CodebaseRepositoryReference` records
/// which *repository* it's linked to and at what ref — the two can eventually coexist (a
/// GitHub-sourced codebase whose folder is also backed by a shared `GitRepository` for the same
/// remote, rather than its own independent clone).
struct CodebaseRepositoryReference: Codable, Hashable {
    /// The repository's remote URL, with any embedded credentials already stripped (see
    /// `GitRepository`'s own normalization in `AcaiGit`) — persisted state must never retain a
    /// credential-bearing URL.
    var remoteURL: URL
    /// A branch, tag, or commit SHA.
    var ref: String
    /// The subdirectory within the repository this codebase actually points at (e.g. one package
    /// of a monorepo). `nil` means the codebase is the repository's whole tree.
    var subpath: String?

    init(remoteURL: URL, ref: String, subpath: String? = nil) {
        self.remoteURL = remoteURL
        self.ref = ref
        self.subpath = subpath
    }
}
