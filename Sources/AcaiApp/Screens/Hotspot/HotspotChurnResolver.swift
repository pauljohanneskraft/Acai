import AcaiGit
import Foundation

/// Churn from the codebase's hub clone when one exists, else from its local folder, which a
/// detected local git checkout never has a hub clone of.
struct HotspotChurnResolver {
    let codebase: Codebase
    let gitRepositoriesDir: URL

    /// `nil` when no git history is reachable for this codebase.
    func churnByFile(limit: Int = 50) throws -> [String: Int]? {
        if let hubResult = try hubChurnByFile(limit: limit) {
            return hubResult
        }
        return try localChurnByFile(limit: limit)
    }

    private func hubChurnByFile(limit: Int) throws -> [String: Int]? {
        guard let reference = codebase.repository else { return nil }
        let hub = GitRepository(remoteURL: reference.remoteURL, storeDirectory: gitRepositoriesDir)
        guard hub.isCloned else { return nil }
        let raw = try hub.churnByFile(ref: reference.ref, limit: limit)
        return RepositorySubpath(prefix: reference.subpath ?? "").offsetting(raw)
    }

    private func localChurnByFile(limit: Int) throws -> [String: Int]? {
        try ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
            .withResolvedURL { url -> [String: Int]? in
                try DirectoryChurn(directory: url).byFile(ref: codebase.pinnedRevision ?? "HEAD", limit: limit)
            }
    }
}
