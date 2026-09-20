import AcaiGit
import Foundation

/// One shared `AcaiGit.GitRepository`'s reverse index: every codebase, across every project, whose
/// `Codebase.repository` references it — the Repositories sidebar/detail needs this to show
/// "used by N codebases". A repository no codebase references has no entry — its clone is deleted
/// with its last worktree.
struct RepositoryIndexEntry: Identifiable, Hashable {
    var remoteURL: URL
    var codebases: [Codebase]
    var id: URL { remoteURL }
}

/// Builds the repository → codebases reverse index off a plain list of projects — a pure
/// computation over already-in-memory data, cheap to call from a view body. Two spellings of one
/// remote (`…/repo` and `…/repo.git`) are one repository, as they are one shared clone on disk.
struct RepositoryIndex {
    let projects: [Project]

    func entries() -> [RepositoryIndexEntry] {
        var entriesByIdentity: [String: RepositoryIndexEntry] = [:]
        for codebase in projects.flatMap(\.codebases) {
            guard let remoteURL = codebase.repository?.remoteURL else { continue }
            let identity = GitRepository(remoteURL: remoteURL, storeDirectory: URL(fileURLWithPath: "/")).identity
            entriesByIdentity[identity, default: RepositoryIndexEntry(remoteURL: remoteURL, codebases: [])]
                .codebases.append(codebase)
        }
        return entriesByIdentity.values.sorted { $0.remoteURL.absoluteString < $1.remoteURL.absoluteString }
    }
}
