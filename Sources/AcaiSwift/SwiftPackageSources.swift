import Foundation
import AcaiCore

/// Turns a manifest's declared targets into the paths a parser should read, following SwiftPM's own
/// layout rules: a declared `path`, else the first predefined directory for the target's kind that
/// exists on disk; `sources` narrows a target to the listed subpaths, `exclude` removes them.
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
            guard let directory = self.directory(for: target) else { continue }
            sourceDirs.append(contentsOf: sources(of: target, in: directory))
            excludedPaths.append(contentsOf: target.exclude.map { directory.child($0) })
        }
        guard !sourceDirs.isEmpty else { return .probe(reason: "no declared target directory exists") }
        return .resolved(
            sourceDirs: sourceDirs.removingDuplicates { $0.path },
            excludedPaths: excludedPaths.removingDuplicates { $0.path }
        )
    }

    private func sources(of target: SwiftPackageManifest.Target, in directory: URL) -> [URL] {
        guard let sources = target.sources else { return [directory] }
        return sources.map { directory.child($0) }.filter { $0.existsOnDisk }
    }

    private func directory(for target: SwiftPackageManifest.Target) -> URL? {
        if let path = target.path {
            let declared = root.child(path)
            return declared.existsOnDisk ? declared : nil
        }
        return target.kind.defaultDirectories
            .lazy
            .map { root.child($0).child(target.name) }
            .first { $0.existsOnDisk }
    }
}

extension URL {
    fileprivate func child(_ path: String) -> URL {
        appendingPathComponent(path).standardizedFileURL
    }

    fileprivate var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
