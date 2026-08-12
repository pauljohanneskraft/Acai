import Foundation

/// One shared `AcaiGit.GitRepository`'s reverse index: every codebase, across every project, whose
/// `Codebase.repository` references it — the Repositories sidebar/detail needs this to show
/// "used by N codebases" and to block removal while any codebase still depends on it.
struct RepositoryIndexEntry: Identifiable, Hashable {
    var remoteURL: URL
    var codebases: [Codebase]
    var id: URL { remoteURL }
}

/// Builds the repository → codebases reverse index off a plain list of projects — a pure
/// computation over already-in-memory data (no filesystem or network access), so it's cheap to
/// call from a view body and easy to unit test without touching disk.
struct RepositoryIndex {
    let projects: [Project]

    /// One entry per distinct remote URL referenced by at least one codebase, sorted by remote URL
    /// for a stable display order.
    func entries() -> [RepositoryIndexEntry] {
        var codebasesByRemote: [URL: [Codebase]] = [:]
        for codebase in projects.flatMap(\.codebases) {
            guard let remoteURL = codebase.repository?.remoteURL else { continue }
            codebasesByRemote[remoteURL, default: []].append(codebase)
        }
        return codebasesByRemote
            .map { RepositoryIndexEntry(remoteURL: $0.key, codebases: $0.value) }
            .sorted { $0.remoteURL.absoluteString < $1.remoteURL.absoluteString }
    }
}
