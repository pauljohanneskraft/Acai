import Foundation

/// Each file's raw, pre-enrichment parse output, keyed by relative path and stamped with the
/// `(modified, size)` it was parsed at.
struct ParsedFileCache: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    struct Entry: Codable, Equatable, Sendable {
        var modified: Date
        var size: Int
        var artifact: CodeArtifact
    }

    private var formatVersion: Int
    private var schemaVersion: Int
    private var build: ToolBuild
    private var entriesByRelativePath: [String: Entry]

    init(
        build: ToolBuild,
        schemaVersion: Int = CodeArtifact.currentSchemaVersion,
        entriesByRelativePath: [String: Entry] = [:]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.schemaVersion = schemaVersion
        self.build = build
        self.entriesByRelativePath = entriesByRelativePath
    }

    func isWritten(by build: ToolBuild) -> Bool {
        formatVersion == Self.currentFormatVersion
            && schemaVersion == CodeArtifact.currentSchemaVersion
            && self.build == build
    }

    func fragment(for fingerprint: SourceFileFingerprint) -> CodeArtifact? {
        guard let entry = entriesByRelativePath[fingerprint.relativePath],
              entry.modified == fingerprint.modified, entry.size == fingerprint.size
        else { return nil }
        return entry.artifact
    }
}

/// A file's cache identity, read from the file itself.
struct SourceFileFingerprint {
    /// Covers filesystems with second-granular timestamps, where a same-size rewrite within the same
    /// second as the last one leaves `(modified, size)` unchanged.
    static let settlingInterval: TimeInterval = 2

    let relativePath: String
    let modified: Date
    let size: Int
    /// Whether `(modified, size)` can be trusted to identify the content; an unsettled file's parse
    /// is used but never persisted.
    let isSettled: Bool

    /// The symlink is resolved first so a link is fingerprinted by what it points at.
    init?(file: URL, relativeTo rootURL: URL, now: Date = Date()) {
        let resolvedPath = file.resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
              let modified = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        self.relativePath = file.relativePath(from: rootURL)
        self.modified = modified
        self.size = size
        self.isSettled = modified < now.addingTimeInterval(-Self.settlingInterval)
    }

    func entry(for artifact: CodeArtifact) -> ParsedFileCache.Entry {
        ParsedFileCache.Entry(modified: modified, size: size, artifact: artifact)
    }
}
