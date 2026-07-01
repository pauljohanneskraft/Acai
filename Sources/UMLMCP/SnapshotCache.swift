import Foundation
import UMLCore
import UMLLibrary

/// Thread-safe cache of enriched `CodeArtifact` snapshots, keyed on canonical path + filesystem
/// modification time. Repeated analysis calls for the same unmodified tree are free after the first.
actor SnapshotCache {
    private struct Key: Hashable {
        var path: String
        var mtime: Date
    }

    private var store: [Key: CodeArtifact] = [:]

    /// Returns a cached artifact for `path` if it was parsed when its mtime matched the current one,
    /// otherwise parses fresh, caches, and returns it.
    func artifact(
        at path: String,
        languages: [CodeArtifact.SourceLanguage] = []
    ) throws -> CodeArtifact {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError.invalidPath(path)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast
        let key = Key(path: url.path, mtime: mtime)
        if let cached = store[key] {
            return cached
        }
        let artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: languages)
        store[key] = artifact
        return artifact
    }
}
