import AcaiCore
import AcaiGit
import Foundation

/// Produces a codebase's `CodeArtifact` as it was at a git revision, for the diagram delta ("old"
/// side). Extracts that revision's tree into a temporary directory via `AcaiGit.GitDiffSnapshot`
/// and analyzes it — read-only: the working tree, index, and HEAD are never touched. The temp
/// directory is removed afterwards. No `Process`/shell-git dependency, so this works identically
/// on iOS/iPadOS and macOS.
struct GitRevisionSnapshot {
    /// The codebase directory (may be the repo root or any subdirectory of it).
    let directory: URL
    /// A git revision: `HEAD`, a branch/tag name, a SHA, `HEAD~3`, …
    let reference: String

    /// Analyzes the codebase's subtree at `reference` and returns the enriched artifact.
    ///
    /// `fileFilter` should be the same codebase's current `Codebase.fileFilter` — the working-tree
    /// side of a delta comparison already applies it, so omitting it here would make every excluded
    /// file's types look like a spurious "removed" diff once a filter is configured.
    func artifact(analyzer: CodebaseAnalyzer = .init(), fileFilter: FileFilter? = nil) throws -> CodeArtifact {
        let extracted = try GitDiffSnapshot(directory: directory, reference: reference).extractedDirectory()
        defer { try? FileManager.default.removeItem(at: extracted) }
        return try analyzer.enrichedArtifact(at: extracted, fileFilter: fileFilter)
    }
}
