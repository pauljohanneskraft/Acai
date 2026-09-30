import AcaiGit
import Foundation

/// What one codebase's history could say about its findings.
enum FindingBlameOutcome {
    /// Keyed by the codebase-relative paths the findings named.
    case blamed([String: [ClosedRange<Int>: GitBlame.Line]])
    case noHistory
    /// Only a shallow cut of the history is present, which would misattribute every older line.
    case historyNotFetched
}

/// Line authorship from the codebase's hub clone when one exists, else from its local folder, which
/// a detected local git checkout never has a hub clone of — the same resolution
/// `HotspotChurnResolver` does for churn.
struct FindingBlameResolver {
    let codebase: Codebase
    let gitRepositoriesDir: URL

    func lastTouched(rangesByFile: [String: Set<ClosedRange<Int>>]) throws -> FindingBlameOutcome {
        do {
            if let hubResult = try hubLastTouched(rangesByFile: rangesByFile) {
                return .blamed(hubResult)
            }
            return try localLastTouched(rangesByFile: rangesByFile).map(FindingBlameOutcome.blamed) ?? .noHistory
        } catch is HistoryNotFetched {
            return .historyNotFetched
        }
    }

    /// Blames the commit the managed checkout was last synced to — the one its index was built
    /// from — rather than wherever the ref has moved since.
    private func hubLastTouched(
        rangesByFile: [String: Set<ClosedRange<Int>>]
    ) throws -> [String: [ClosedRange<Int>: GitBlame.Line]]? {
        guard let reference = codebase.repository else { return nil }
        let hub = GitRepository(remoteURL: reference.remoteURL, storeDirectory: gitRepositoriesDir)
        guard hub.isCloned else { return nil }
        let subpath = RepositorySubpath(prefix: reference.subpath ?? "")
        let revision = codebase.managedCheckout?.lastSyncedCommitSHA ?? reference.ref
        return subpath.offsetting(
            try hub.blame(rangesByFile: subpath.prefixing(rangesByFile), ref: revision))
    }

    /// A folder analysed as its working tree is blamed as its working tree, so uncommitted edits
    /// shift no finding onto someone else's line.
    private func localLastTouched(
        rangesByFile: [String: Set<ClosedRange<Int>>]
    ) throws -> [String: [ClosedRange<Int>: GitBlame.Line]]? {
        let source = codebase.pinnedRevision.map(GitBlame.Source.revision) ?? .workingTree
        return try ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
            .withResolvedURL { url -> [String: [ClosedRange<Int>: GitBlame.Line]]? in
                try DirectoryBlame(directory: url).lastTouched(inRangesByFile: rangesByFile, source: source)
            }
    }
}
