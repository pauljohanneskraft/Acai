import Foundation
import MCP
import UMLLibrary

/// A cheap change-signature for a source tree: the newest file modification time plus the file count,
/// over everything under a root except build/VCS output. Two signatures compare equal when nothing an
/// analysis would read has changed, so the snapshot cache can reuse a parse across a whole task and
/// still notice an edit. A value computed from the tree (`SourceTreeSignature(root:)`).
struct SourceTreeSignature: Equatable, Sendable {
    let latestModification: TimeInterval
    let fileCount: Int

    /// Directories whose contents never affect an analysis — skipped wholesale so the walk stays cheap
    /// and edits to build products don't invalidate the snapshot.
    private static let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "node_modules", "DerivedData", "build",
        ".gradle", "dist", "Pods", "__pycache__", ".venv", "venv"
    ]

    init(root: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isRegularFileKey]
        var latest: TimeInterval = 0
        var count = 0
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
            if let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate,
               modified > latest {
                latest = modified
            }
        }
        self.latestModification = latest
        self.fileCount = count
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

    /// The enriched artifact for `path`. Reuses the cached snapshot when the tree signature is
    /// unchanged and `refresh` is false; otherwise analyzes and caches. Throws `invalidParams` when the
    /// path does not exist.
    func artifact(path: String, languageNames: [String] = [], refresh: Bool = false) throws -> CodeArtifact {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPError.invalidParams("Path does not exist: \(path)")
        }
        let key = url.path
        let signature = SourceTreeSignature(root: url)
        if !refresh, let cached = entries[key], cached.signature == signature {
            return cached.artifact
        }
        let artifact = try service.analyzeProject(
            at: url, allowedLanguages: languageResolver.resolve(names: languageNames))
        analysisCount += 1
        entries[key] = Entry(signature: signature, artifact: artifact)
        return artifact
    }
}
