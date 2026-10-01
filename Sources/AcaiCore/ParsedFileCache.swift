import Foundation

/// A per-file cache of raw parse results — each file's own ``CodeParser/parse(source:fileName:)``
/// output, before enrichment — keyed by `(relativePath, modified, size)`. Consulted by
/// ``AnalysisService/analyzeProject(at:allowedLanguages:respectingGitignore:reusing:includingFile:)``
/// so a single edited file in an otherwise-unchanged tree reparses only that file.
///
/// Immutable by design: every file in a project is re-evaluated on each analysis (a changed file is
/// reparsed, an unchanged one is carried forward, a removed one is dropped), so the cache this type's
/// consumer builds is always complete for the tree it just saw — never a mutated, possibly-stale
/// accumulation from several trees.
public struct ParsedFileCache: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    /// One file's cached parse result.
    public struct Entry: Codable, Equatable, Sendable {
        public var modified: Date
        public var size: Int
        public var artifact: CodeArtifact
    }

    private var formatVersion: Int
    private var toolVersion: String?
    private var entriesByRelativePath: [String: Entry]

    /// An empty cache — every file is a miss, matching a cold analysis.
    public init() {
        self.formatVersion = Self.currentFormatVersion
        self.toolVersion = nil
        self.entriesByRelativePath = [:]
    }

    init(toolVersion: String, entriesByRelativePath: [String: Entry]) {
        self.formatVersion = Self.currentFormatVersion
        self.toolVersion = toolVersion
        self.entriesByRelativePath = entriesByRelativePath
    }

    /// This cache, or an empty one when it was written by a different format or tool version.
    /// Parsing behaviour can change between tool versions, so a version mismatch discards every
    /// entry rather than trusting any of them individually.
    func validated(forToolVersion toolVersion: String) -> ParsedFileCache {
        guard formatVersion == Self.currentFormatVersion, self.toolVersion == toolVersion else {
            return ParsedFileCache()
        }
        return self
    }

    /// The cached fragment for `relativePath`, only when its fingerprint still matches.
    func fragment(forRelativePath relativePath: String, modified: Date, size: Int) -> CodeArtifact? {
        guard let entry = entriesByRelativePath[relativePath], entry.modified == modified, entry.size == size
        else { return nil }
        return entry.artifact
    }
}
