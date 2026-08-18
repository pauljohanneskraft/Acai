import AcaiCore
import AcaiGit
import Foundation

/// Read-only: the working tree, index, and HEAD are never touched. No `Process`/shell-git
/// dependency, so this works identically on iOS/iPadOS and macOS.
struct GitRevisionSnapshot: Sendable {
    let directory: URL
    let reference: String

    /// `fileFilter` should be the same codebase's current `Codebase.fileFilter` — the working-tree
    /// side of a delta comparison already applies it, so omitting it here would make every excluded
    /// file's types look like a spurious "removed" diff once a filter is configured.
    func artifact(
        analyzer: CodebaseAnalyzing = CodebaseAnalyzer(), fileFilter: FileFilter? = nil
    ) throws -> CodeArtifact {
        let extracted = try GitDiffSnapshot(directory: directory, reference: reference).extractedDirectory()
        defer { try? FileManager.default.removeItem(at: extracted) }
        return try analyzer.enrichedArtifact(at: extracted, fileFilter: fileFilter)
    }
}
