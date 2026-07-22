import AcaiCore
import AcaiGit
import Foundation

/// Produces a codebase's `CodeArtifact` as it was at a git revision, for the diagram delta ("old"
/// side). Extracts that revision's tree into a temporary directory via `AcaiGit.GitDiffSnapshot`
/// and analyzes it — **read-only**: the working tree, index and HEAD are never touched. The temp
/// directory is removed afterwards. Cross-platform (no `Process`/`/usr/bin/git`/`/usr/bin/tar`
/// dependency, unlike the shell-based version this replaces), so diagram delta comparison works
/// identically on iOS/iPadOS and macOS.
struct GitRevisionSnapshot {
    /// The codebase directory (may be the repo root or any subdirectory of it).
    let directory: URL
    /// A git revision: `HEAD`, a branch/tag name, a SHA, `HEAD~3`, …
    let reference: String

    /// Analyzes the codebase's subtree at `reference` and returns the enriched artifact.
    ///
    /// `fileFilter` should be the same codebase's current `Codebase.fileFilter` — the "new"
    /// (working-tree) side of a delta comparison already applies it (`reindex(codebaseID:)`), so
    /// omitting it here would make every excluded file's types look like a spurious "removed" (red)
    /// diff the moment a filter is actually configured, since only the new side would have dropped
    /// them.
    func artifact(analyzer: CodebaseAnalyzer = .init(), fileFilter: FileFilter? = nil) throws -> CodeArtifact {
        let extracted = try GitDiffSnapshot(directory: directory, reference: reference).extractedDirectory()
        defer { try? FileManager.default.removeItem(at: extracted) }
        return try analyzer.enrichedArtifact(at: extracted, fileFilter: fileFilter)
    }
}
