import Foundation

/// Records which shared git repository (`AcaiGit`'s `GitRepository`) a `Codebase`'s content is
/// drawn from, and at what ref/subpath.
///
/// Distinct from `GitHubSource`, which records how the codebase's *folder* came to exist (an
/// in-app GitHub clone) rather than which *repository* it's linked to — the two can coexist.
struct CodebaseRepositoryReference: Codable, Hashable {
    /// Credentials already stripped — persisted state must never retain a credential-bearing URL.
    var remoteURL: URL
    /// A branch, tag, or commit SHA.
    var ref: String
    /// `nil` means the codebase is the repository's whole tree.
    var subpath: String?

    init(remoteURL: URL, ref: String, subpath: String? = nil) {
        self.remoteURL = remoteURL
        self.ref = ref
        self.subpath = subpath
    }
}
