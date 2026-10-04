import Foundation

/// A per-file cache of raw parse results — each file's own ``CodeParser/parse(source:fileName:)``
/// output, before enrichment — keyed by `(relativePath, modified, size)`. The value an
/// ``AnalysisCache`` reads and writes, so a single edited file in an otherwise-unchanged tree
/// reparses only that file.
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

    /// The cached fragment for `fingerprint`'s file, only when the file on disk still matches the
    /// fingerprint the entry was stamped with.
    func fragment(for fingerprint: SourceFileFingerprint) -> CodeArtifact? {
        guard let entry = entriesByRelativePath[fingerprint.relativePath],
              entry.modified == fingerprint.modified, entry.size == fingerprint.size
        else { return nil }
        return entry.artifact
    }
}

/// One file's identity for cache purposes: the fingerprint a ``ParsedFileCache/Entry`` is keyed and
/// stamped with, read from the file itself.
struct SourceFileFingerprint {
    let relativePath: String
    let modified: Date
    let size: Int

    /// `nil` when the file's attributes can't be read — it will fail to read for parsing too,
    /// moments later, and surface as the usual `.unreadable` diagnostic there.
    ///
    /// The symlink is resolved first so a link is fingerprinted by what it points at, matching how
    /// the file is later read and size-checked.
    init?(file: URL, relativeTo rootURL: URL) {
        let resolvedPath = file.resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
              let modified = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        self.relativePath = file.relativePath(from: rootURL)
        self.modified = modified
        self.size = size
    }

    /// This file's cache entry for `artifact`.
    func entry(for artifact: CodeArtifact) -> ParsedFileCache.Entry {
        ParsedFileCache.Entry(modified: modified, size: size, artifact: artifact)
    }
}
