import Foundation
import AcaiCore

/// A `package.json`'s `workspaces`, in both the shapes npm accepts: a bare array of globs, and the
/// Yarn-style object whose `packages` key holds them. A `!`-prefixed glob excludes what it matches,
/// as npm treats it.
struct NodeWorkspaces {
    private let included: [String]
    private let excluded: [String]
    private let excludedDirectories: Set<String>

    /// Nil when the manifest is unreadable or declares no workspaces — the ordinary single-package case.
    init?(manifestAt url: URL, excludingDirectories excludedDirectories: Set<String>) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let patterns: [String]
        switch json["workspaces"] {
        case let values as [String]: patterns = values
        case let object as [String: Any]: patterns = object["packages"] as? [String] ?? []
        default: patterns = []
        }
        guard !patterns.isEmpty else { return nil }

        included = patterns.filter { !$0.hasPrefix("!") }
        excluded = patterns.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) }
        self.excludedDirectories = excludedDirectories
    }

    /// Every directory a glob matches that is itself a package, in declaration order and de-duplicated.
    func packageRoots(in root: URL) -> [URL] {
        let excludedRoots = Set(
            excluded.flatMap { DirectoryGlob($0, excludingDirectories: excludedDirectories).directories(in: root) }
                .map(\.path))
        return included
            .flatMap { DirectoryGlob($0, excludingDirectories: excludedDirectories).directories(in: root) }
            .filter { !excludedRoots.contains($0.path) && $0.path != root.standardizedFileURL.path }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("package.json").path) }
            .removingDuplicates { $0.path }
    }
}
