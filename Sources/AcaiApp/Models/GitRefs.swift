// `Process` doesn't exist in the iOS SDK — macOS-only, see `GitCommand.swift`.
#if os(macOS)
import Foundation

/// Lists local branch and tag names for a codebase directory — backs the ref picker in
/// `DeltaComparisonBar`, so "Compare vs git" offers a pickable list instead of only a freeform ref
/// field. Read-only, mirrors `GitRevisionSnapshot`'s process-running approach.
struct GitRefs {
    /// The codebase directory (may be the repo root or any subdirectory of it).
    let directory: URL

    /// Branch names first (most recently used comparison target), then tags, each alphabetical.
    func names() throws -> [String] {
        let output = try GitCommand(
            directory: directory,
            arguments: ["for-each-ref", "--format=%(refname:short)\t%(refname)", "refs/heads", "refs/tags"]
        ).run()
        let lines = output.split(separator: "\n").map(String.init)
        let branches = lines.filter { $0.contains("\trefs/heads/") }.map(shortName)
        let tags = lines.filter { $0.contains("\trefs/tags/") }.map(shortName)
        return branches.sorted() + tags.sorted()
    }

    private func shortName(_ line: String) -> String {
        String(line.split(separator: "\t", maxSplits: 1).first ?? "")
    }
}
#endif
