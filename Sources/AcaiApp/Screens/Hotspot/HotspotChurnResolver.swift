import AcaiGit
import Foundation

/// Resolves and walks the git history behind one codebase's churn count, for the Hotspot diagram.
/// A plain value (constructed with everything it needs, no environment/view-model dependency) so
/// the walk can run from inside a `Task.detached` closure without capturing a `@MainActor` view
/// model — this touches the filesystem and a git object store, so it must never run on the main
/// actor.
///
/// Tries two sources, in order:
/// 1. `codebase.repository`'s shared `GitRepository` hub clone, when it's actually been cloned —
///    this is the common case for a GitHub-sourced codebase.
/// 2. The codebase's own local folder directly, via `GitRepositoryRoot.find()` — the common case
///    for a transparently-detected local git folder, which is deliberately never cloned into the
///    shared hub, so checking only the hub would silently show "no git history" for the most
///    ordinary local-repo case.
///
/// Either source's raw, repository-root-relative paths are then offset back down to the paths
/// `SourceLocation.filePath` actually uses (codebase-root-relative), so the churn map's keys line up
/// with `HotspotChartData`'s complexity map.
struct HotspotChurnResolver {
    let codebase: Codebase
    let gitRepositoriesDir: URL

    /// `nil` when no git history is reachable at all for this codebase (a plain, non-git local
    /// folder, or a git-linked codebase whose shared clone hasn't been synced yet) — distinct from
    /// an empty (but non-`nil`) result, which means a real repository with (as yet) no history to
    /// report.
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
        return offsetting(raw, byRepositoryRelativePrefix: reference.subpath ?? "")
    }

    private func localChurnByFile(limit: Int) throws -> [String: Int]? {
        try ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
            .withResolvedURL { url -> [String: Int]? in
                guard let root = GitRepositoryRoot(directory: url).find() else { return nil }
                let raw = try GitChurn(directory: root).byFile(ref: "HEAD", limit: limit)
                return offsetting(raw, byRepositoryRelativePrefix: relativePrefix(from: root, to: url))
            }
    }

    /// The codebase-directory's path relative to the repository `root` it was found under (e.g.
    /// `"Sub/Package"` for a monorepo subdirectory codebase), or `""` when the codebase directory
    /// *is* the repository root.
    private func relativePrefix(from root: URL, to codebaseDirectory: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let codebasePath = codebaseDirectory.standardizedFileURL.path
        guard codebasePath != rootPath, codebasePath.hasPrefix(rootPath + "/") else { return "" }
        return String(codebasePath.dropFirst(rootPath.count + 1))
    }

    /// Strips `prefix` (when non-empty) off every key, dropping entries outside it — turning
    /// repository-root-relative paths into codebase-root-relative ones.
    private func offsetting(_ raw: [String: Int], byRepositoryRelativePrefix prefix: String) -> [String: Int] {
        guard !prefix.isEmpty else { return raw }
        let normalized = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value -> (String, Int)? in
            guard key.hasPrefix(normalized) else { return nil }
            return (String(key.dropFirst(normalized.count)), value)
        })
    }
}
