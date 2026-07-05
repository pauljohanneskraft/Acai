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
        // A single file (e.g. a `.json` baseline) signs on its own mtime — the directory walk below
        // enumerates nothing for a non-directory.
        if let values = try? root.resourceValues(forKeys: keys), values.isRegularFile == true {
            self.latestModification = values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            self.fileCount = 1
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
