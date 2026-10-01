import Foundation
import AcaiCore

/// Turns a manifest's declared targets into the paths a parser should read, following SwiftPM's own
/// layout rules: a declared `path`, else the first predefined directory for the target's kind that
/// exists on disk; `sources` narrows a target to the listed subpaths, `exclude` and `resources`
/// remove them.
struct SwiftPackageSources {

    enum Outcome {
        case resolved(sourceDirs: [URL], excludedPaths: [URL])
        /// Nothing trustworthy to go on, for the stated reason: probe the filesystem instead.
        case probe(reason: String)
    }

    private let root: URL
    private let manifest: SwiftPackageManifest

    init(root: URL, manifest: SwiftPackageManifest) {
        self.root = root
        self.manifest = manifest
    }

    var outcome: Outcome {
        if let reason = manifest.incompleteReason { return .probe(reason: reason) }
        var sourceDirs: [URL] = []
        var excludedPaths: [URL] = []
        for target in manifest.targets {
            if let path = target.path, !root.child(path).isContained(in: root) {
                return .probe(reason: "target `\(target.name)` declares a path outside the package")
            }
            guard let directory = self.directory(for: target) else {
                return .probe(reason: "the directory of target `\(target.name)` was not found")
            }
            sourceDirs.append(contentsOf: sources(of: target, in: directory))
            excludedPaths.append(contentsOf: children(target.exclude + target.resources, of: directory))
        }
        guard !sourceDirs.isEmpty else { return .probe(reason: "no declared target directory exists") }
        return .resolved(
            sourceDirs: sourceDirs.removingDuplicates { $0.path },
            excludedPaths: excludedPaths.removingDuplicates { $0.path }
        )
    }

    private func sources(of target: SwiftPackageManifest.Target, in directory: URL) -> [URL] {
        guard let sources = target.sources else { return [directory] }
        return children(sources, of: directory).filter(\.existsOnDisk)
    }

    /// `exclude`, `sources` and `resources` entries are target-relative, and SwiftPM rejects one that
    /// leaves the target — so a `"../Other"` widening a target into a sibling is dropped here.
    private func children(_ paths: [String], of directory: URL) -> [URL] {
        paths.map { directory.child($0) }.filter { $0.isContained(in: directory) }
    }

    private func directory(for target: SwiftPackageManifest.Target) -> URL? {
        if let path = target.path {
            let declared = root.child(path)
            return declared.existsOnDisk ? declared : nil
        }
        let defaults = target.kind.defaultDirectories.lazy.map { root.child($0) }
        if let named = defaults.map({ $0.child(target.name) }).first(where: \.existsOnDisk) {
            return named
        }
        // SwiftPM lets the only target of its kind keep its sources directly in the predefined directory.
        guard manifest.targets.filter({ $0.kind == target.kind }).count == 1 else { return nil }
        return target.kind.flatLayoutDirectories.lazy.map { root.child($0) }.first { $0.existsOnDisk }
    }
}

extension URL {
    fileprivate func child(_ path: String) -> URL {
        appendingPathComponent(path).standardizedFileURL
    }

    fileprivate var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    fileprivate func isContained(in ancestor: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.path
        let ownPath = standardizedFileURL.path
        return ownPath == ancestorPath || ownPath.hasPrefix(ancestorPath + "/")
    }
}
