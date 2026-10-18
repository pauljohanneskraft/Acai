import AcaiCore
import Foundation

/// The choice the Add Codebase sheet offers once a picked folder turns out to hold several projects:
/// which roots to take, and whether to take them as one codebase or one each.
struct MultiRootPlan: Equatable {
    var roots: [CodeArtifact.DiscoveredRoot] = []
    var checkedPaths: Set<String> = []
    var combinesIntoOne = false

    /// One root is the ordinary case and needs no choice — the folder *is* the project.
    var isOffered: Bool { roots.count > 1 }

    var checkedRoots: [CodeArtifact.DiscoveredRoot] {
        roots.filter { checkedPaths.contains($0.path) }
    }

    /// Combining takes the whole folder, so the checkmarks don't gate it; splitting needs one.
    var isSatisfiable: Bool { combinesIntoOne || !checkedRoots.isEmpty }

    func isChecked(_ root: CodeArtifact.DiscoveredRoot) -> Bool {
        checkedPaths.contains(root.path)
    }

    mutating func setChecked(_ isChecked: Bool, for root: CodeArtifact.DiscoveredRoot) {
        if isChecked {
            checkedPaths.insert(root.path)
        } else {
            checkedPaths.remove(root.path)
        }
    }

    /// Each checked root's folder beneath `parent`. A root path of `"."` is the picked folder itself,
    /// which `appendingPathComponent` would otherwise turn into a `foo/.` sibling of it.
    func folders(under parent: URL) -> [URL] {
        checkedRoots.map { $0.path == "." ? parent : parent.appendingPathComponent($0.path) }
    }
}
