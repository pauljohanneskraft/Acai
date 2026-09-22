import Foundation
import MCP
import AcaiCore
import AcaiLibrary

/// The in-process parse cache behind every tool: one enriched `CodeArtifact` per project path, reused
/// across a task until the tree changes (or a tool passes `refresh`). On an in-memory miss it consults
/// the shared `AnalysisStore` before re-analyzing — so a second MCP session over the same tree, or one
/// already indexed by the CLI or the app, starts warm — and writes back what it analyzes so the next
/// session (in this process or another) can do the same. An `actor` so concurrent tool calls serialize
/// safely on the cache.
actor AnalysisSnapshotCache {
    private struct Entry {
        let fingerprint: CodeStateFingerprint
        let artifact: CodeArtifact
    }

    private let service: AnalysisService
    private let store: AnalysisStore
    private let languageResolver = SourceLanguageResolver()
    private var entries: [String: Entry] = [:]

    /// Counts fresh analyses only (in-memory and on-disk misses alike), so this is the observable
    /// proof a snapshot is being reused rather than recomputed.
    private(set) var analysisCount = 0

    init(service: AnalysisService = .standard, store: AnalysisStore = .standard) {
        self.service = service
        self.store = store
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
        let fingerprint = SourceTreeFingerprint(directory: url).compute()
        if !refresh, let cached = entries[key], cached.fingerprint == fingerprint {
            return cached.artifact
        }
        let toolVersion = AcaiConstants.standard.toolVersion
        if !refresh, case .entry(let stored) = store.lookup(forResolvedPath: key),
           stored.isCurrent(sourcePath: key, fingerprint: fingerprint, toolVersion: toolVersion) {
            try validateSchemaVersion(of: stored.artifact, at: key)
            entries[key] = Entry(fingerprint: fingerprint, artifact: stored.artifact)
            return stored.artifact
        }
        let artifact: CodeArtifact
        if !isDirectory.boolValue && url.pathExtension == "json" {
            artifact = try decodeArtifact(at: url)
        } else {
            artifact = try service.analyzeProject(
                at: url, allowedLanguages: languageResolver.resolve(names: languageNames))
            _ = try? store.write(artifact, sourcePath: key, fingerprint: fingerprint)
        }
        analysisCount += 1
        entries[key] = Entry(fingerprint: fingerprint, artifact: artifact)
        return artifact
    }

    private func decodeArtifact(at url: URL) throws -> CodeArtifact {
        let artifact: CodeArtifact
        do {
            artifact = try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: url))
        } catch {
            throw MCPError.invalidParams(
                "Could not read an Açaí artifact from \(url.path): \(error.localizedDescription)")
        }
        try validateSchemaVersion(of: artifact, at: url.path)
        return artifact
    }

    /// Rejects an artifact newer than this build understands, naming both versions rather than
    /// letting the mismatch surface later as some unrelated tool failure.
    private func validateSchemaVersion(of artifact: CodeArtifact, at path: String) throws {
        guard artifact.schemaVersion <= CodeArtifact.currentSchemaVersion else {
            throw MCPError.invalidParams(
                "Açaí artifact at \(path) has schema version \(artifact.schemaVersion), but this build of Açaí "
                + "supports up to \(CodeArtifact.currentSchemaVersion). Regenerate it with a newer build."
            )
        }
    }
}
