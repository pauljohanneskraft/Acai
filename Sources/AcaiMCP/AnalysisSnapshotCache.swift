import Foundation
import MCP
import AcaiLibrary

/// A cheap change-signature for a source tree: newest modification time, file count, and an
/// order-independent digest folding each file's `(relativePath, mtime, size)` (skipping build/VCS
/// output). The digest is what catches a rename/move or content-swap — those preserve mtime and
/// count alone.
struct SourceTreeSignature: Equatable, Sendable {
    let latestModification: TimeInterval
    let fileCount: Int
    /// Commutative sum, so it's enumeration-order-independent.
    let contentDigest: UInt64

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
        // `root` may be a single `.json` baseline file rather than a directory.
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

private struct FileFingerprint {
    let relativePath: String
    let mtime: TimeInterval
    let size: Int

    /// FNV-1a hash, seed-free so it's deterministic across the process's lifetime.
    var stableHash: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(relativePath)|\(mtime.bitPattern)|\(size)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// The in-process parse cache behind every tool: one enriched `CodeArtifact` per project path, reused
/// across a task until the tree changes (or a tool passes `refresh`). An `actor` so concurrent tool
/// calls serialize safely on the cache.
actor AnalysisSnapshotCache {
    private struct Entry {
        let signature: SourceTreeSignature
        let artifact: CodeArtifact
    }

    private let service: AnalysisService
    private let languageResolver = SourceLanguageResolver()
    private var entries: [String: Entry] = [:]

    /// Counts cache misses only, so this is the observable proof a snapshot is being reused.
    private(set) var analysisCount = 0

    init(service: AnalysisService = .standard) {
        self.service = service
    }

    /// `path` is a source directory to analyze, or a `.json` artifact file to decode (a stored
    /// baseline, used by `acai_diff`).
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

    private func decodeArtifact(at url: URL) throws -> CodeArtifact {
        do {
            return try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: url))
        } catch {
            throw MCPError.invalidParams(
                "Could not read an Açaí artifact from \(url.path): \(error.localizedDescription)")
        }
    }
}
