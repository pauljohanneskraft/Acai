import Foundation
import MCP
import UMLLibrary

/// A cheap change-signature for a source tree: the newest file modification time, the file count, and an
/// order-independent digest folding each file's `(relativePath, mtime, size)`, over everything under a
/// root except build/VCS output. Two signatures compare equal when nothing an analysis would read has
/// changed, so the snapshot cache can reuse a parse across a whole task and still notice an edit. The
/// digest is what makes a rename/move or content-swap visible — those preserve the newest-mtime and the
/// file count, so an mtime+count signature alone would serve a stale parse. A value computed from the
/// tree (`SourceTreeSignature(root:)`).
struct SourceTreeSignature: Equatable, Sendable {
    let latestModification: TimeInterval
    let fileCount: Int
    /// Sum (commutative → enumeration-order-independent) of a stable per-file hash of
    /// `(relativePath, mtime, size)`. Changes when a file is added, removed, edited, moved, or swapped.
    let contentDigest: UInt64

    /// Directories whose contents never affect an analysis — skipped wholesale so the walk stays cheap
    /// and edits to build products don't invalidate the snapshot.
    private static let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "node_modules", "DerivedData", "build",
        ".gradle", "dist", "Pods", "__pycache__", ".venv", "venv"
    ]

    init(root: URL) {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let rootPath = root.standardizedFileURL.path
        var latest: TimeInterval = 0
        var count = 0
        var digest: UInt64 = 0
        // A single file (e.g. a `.json` baseline) signs on its own identity — the directory walk below
        // enumerates nothing for a non-directory.
        if let values = try? root.resourceValues(forKeys: keys), values.isRegularFile == true {
            let mtime = values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            self.latestModification = mtime
            self.fileCount = 1
            self.contentDigest = FileFingerprint(
                relativePath: root.lastPathComponent, mtime: mtime, size: values.fileSize ?? 0).stableHash
            return
        }
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if Self.skippedDirectories.contains(url.lastPathComponent) {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            count += 1
            let mtime = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            if mtime > latest { latest = mtime }
            let relativePath = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
            digest &+= FileFingerprint(
                relativePath: relativePath, mtime: mtime, size: values?.fileSize ?? 0).stableHash
        }
        self.latestModification = latest
        self.fileCount = count
        self.contentDigest = digest
    }
}

/// One file's identity — its path, modification time and size — reduced to a stable hash the signature
/// folds together. A value with the hashing behaviour on it (not a static helper).
private struct FileFingerprint {
    let relativePath: String
    let mtime: TimeInterval
    let size: Int

    /// A stable (seed-free) FNV-1a hash of the file's identity. Deterministic across the process's
    /// lifetime so the in-process cache compares signatures reliably.
    var stableHash: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(relativePath)|\(mtime.bitPattern)|\(size)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// The in-process parse cache behind every tool: one enriched `CodeArtifact` per project path, reused
/// across a task until the tree changes (or a tool passes `refresh`). This is what makes an always-on
/// MCP cheap — a fleet of tool calls over one codebase parses it once. An `actor`, so concurrent tool
/// calls serialize safely on the cache; a real instance, not a static namespace.
actor AnalysisSnapshotCache {
    private struct Entry {
        let signature: SourceTreeSignature
        let artifact: CodeArtifact
    }

    private let service: AnalysisService
    private let languageResolver = SourceLanguageResolver()
    private var entries: [String: Entry] = [:]

    /// How many times a real analysis has run (a cache miss). A cache *hit* does not increment it, so
    /// this is the observable that proves the snapshot is being reused across a task.
    private(set) var analysisCount = 0

    init(service: AnalysisService = .standard) {
        self.service = service
    }

    /// The enriched artifact for `path` — a source directory to analyze, or a `.json` artifact file to
    /// decode (a stored baseline, used by `uml_diff`). Reuses the cached snapshot when the signature is
    /// unchanged and `refresh` is false; otherwise (re)loads and caches. Throws `invalidParams` when the
    /// path does not exist or a `.json` file can't be decoded.
    func artifact(path: String, languageNames: [String] = [], refresh: Bool = false) throws -> CodeArtifact {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw MCPError.invalidParams("Path does not exist: \(path)")
        }
        let key = url.path
        let signature = SourceTreeSignature(root: url)
        if !refresh, let cached = entries[key], cached.signature == signature {
            return cached.artifact
        }
        let artifact: CodeArtifact
        if !isDirectory.boolValue && url.pathExtension == "json" {
            artifact = try decodeArtifact(at: url)
        } else {
            artifact = try service.analyzeProject(
                at: url, allowedLanguages: languageResolver.resolve(names: languageNames))
        }
        analysisCount += 1
        entries[key] = Entry(signature: signature, artifact: artifact)
        return artifact
    }

    /// Decodes a stored `CodeArtifact` JSON file (produced by `uml analyze`/`store`).
    private func decodeArtifact(at url: URL) throws -> CodeArtifact {
        do {
            return try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: url))
        } catch {
            throw MCPError.invalidParams(
                "Could not read a UML artifact from \(url.path): \(error.localizedDescription)")
        }
    }
}
