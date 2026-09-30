import AcaiGit
import Foundation

/// Line authorship from the codebase's hub clone when one exists, else from its local folder, which
/// a detected local git checkout never has a hub clone of — the same resolution
/// `HotspotChurnResolver` does for churn.
struct FindingBlameResolver {
    let codebase: Codebase
    let gitRepositoriesDir: URL

    /// Keyed by the codebase-relative paths the findings named. `nil` when no git history is
    /// reachable for this codebase.
    func lastTouched(linesByFile: [String: Set<Int>]) throws -> [String: [Int: GitBlame.Line]]? {
        if let hubResult = try hubLastTouched(linesByFile: linesByFile) {
            return hubResult
        }
        return try localLastTouched(linesByFile: linesByFile)
    }

    private func hubLastTouched(
        linesByFile: [String: Set<Int>]
    ) throws -> [String: [Int: GitBlame.Line]]? {
        guard let reference = codebase.repository else { return nil }
        let hub = GitRepository(remoteURL: reference.remoteURL, storeDirectory: gitRepositoriesDir)
        guard hub.isCloned else { return nil }
        let subpath = RepositorySubpath(prefix: reference.subpath ?? "")
        return subpath.offsetting(try hub.blame(byFile: subpath.prefixing(linesByFile)))
    }

    private func localLastTouched(
        linesByFile: [String: Set<Int>]
    ) throws -> [String: [Int: GitBlame.Line]]? {
        try ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
            .withResolvedURL { url -> [String: [Int: GitBlame.Line]]? in
                try DirectoryBlame(directory: url).lines(byFile: linesByFile)
            }
    }
}
