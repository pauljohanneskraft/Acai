import Foundation

/// The on-disk analysis store shared by the command line, the MCP server and the app, so indexing a
/// project once is reusable from any of the three. Identity is the standardized, symlink-resolved
/// absolute path of the analyzed source directory — never a name or a UUID, which stay private
/// aliases their own interface keeps (the CLI's `--from <name>`, the app's `Codebase.id`).
///
/// An entry keyed by a resolved path lives at a path-derived file name so every interface converges
/// on the same file. `write(_:sourcePath:fingerprint:named:)` additionally supports the CLI's
/// human-chosen name as the file name, so `acai store <name> <dir>` keeps writing (and `acai list`
/// keeps listing) exactly the files it always has.
public struct AnalysisStore: Sendable {
    public static let standard = AnalysisStore()

    public let directory: URL

    public init(directory: URL = AcaiConstants.standard.analysisDirectory) {
        self.directory = directory
    }

    /// One analysis: the artifact, where it came from, and enough to tell whether it's still
    /// current.
    public struct Entry: Codable, Equatable, Sendable {
        static let currentFormatVersion = 1

        var formatVersion: Int
        public var artifact: CodeArtifact
        public var sourcePath: String
        public var fingerprint: CodeStateFingerprint
        public var writtenAt: Date

        public init(
            artifact: CodeArtifact,
            sourcePath: String,
            fingerprint: CodeStateFingerprint,
            writtenAt: Date = Date()
        ) {
            self.formatVersion = Self.currentFormatVersion
            self.artifact = artifact
            self.sourcePath = sourcePath
            self.fingerprint = fingerprint
            self.writtenAt = writtenAt
        }

        /// Whether this entry can be used as-is for `sourcePath` at `fingerprint`, given the
        /// current tool version — a mismatch on any of the three means "re-analyze", never a
        /// stale result decoded as if it were current.
        public func isCurrent(
            sourcePath: String, fingerprint: CodeStateFingerprint, toolVersion: String
        ) -> Bool {
            self.sourcePath == sourcePath
                && self.fingerprint == fingerprint
                && artifact.metadata.toolVersion == toolVersion
        }
    }

    /// What loading an entry found.
    public enum Lookup: Equatable {
        /// A current-format entry, decoded whole.
        case entry(Entry)
        /// A bare `CodeArtifact` predating the shared store (the CLI's original `acai store`
        /// shape). Still usable via `--from`, but carries no fingerprint or recorded source path,
        /// so it is always considered stale by a caller checking freshness.
        case legacyArtifact(CodeArtifact)
        /// Nothing stored at this location, or the file could not be decoded as either shape.
        case absent
    }

    // MARK: - Lookup

    public func lookup(named name: String) -> Lookup {
        load(at: url(forName: name))
    }

    public func lookup(forResolvedPath path: String) -> Lookup {
        guard let url = existingEntryURL(forResolvedPath: path) else { return .absent }
        return load(at: url)
    }

    /// The file `acai store <name> …` writes and `--from <name>` reads — exposed so callers can
    /// tell a missing entry apart from one that exists but failed to decode.
    public func url(forName name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    // MARK: - Write

    /// Writes `artifact` as the entry for `sourcePath`. When `name` is given, it is written to
    /// (and always addressable at) `<name>.json` — the CLI's alias. Otherwise it converges on
    /// whatever file already holds this path's entry, or a new path-derived file name.
    @discardableResult
    public func write(
        _ artifact: CodeArtifact,
        sourcePath: String,
        fingerprint: CodeStateFingerprint,
        named name: String? = nil
    ) throws -> URL {
        let record = Entry(artifact: artifact, sourcePath: sourcePath, fingerprint: fingerprint)
        let destination = name.map(url(forName:))
            ?? existingEntryURL(forResolvedPath: sourcePath)
            ?? hashedEntryURL(forResolvedPath: sourcePath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: destination, options: .atomic)
        // A named write supersedes any earlier path-derived file for the same path, so a later
        // lookup by path doesn't find a now-stale duplicate.
        if name != nil {
            let hashed = hashedEntryURL(forResolvedPath: sourcePath)
            if hashed != destination {
                try? FileManager.default.removeItem(at: hashed)
            }
        }
        return destination
    }

    /// Removes the stored entry for `path`, under whatever file name it lives at. A no-op when
    /// nothing is stored for this path.
    public func removeEntry(forResolvedPath path: String) throws {
        guard let url = existingEntryURL(forResolvedPath: path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func hashedEntryURL(forResolvedPath path: String) -> URL {
        directory.appendingPathComponent("\(PathDigest(path).hex).json")
    }

    /// The existing file holding `path`'s entry, if any: the path-derived file first (a direct,
    /// cheap check), falling back to a scan of every stored `.json` file's recorded `sourcePath`
    /// so an entry written under a CLI name is still found by path.
    private func existingEntryURL(forResolvedPath path: String) -> URL? {
        let hashed = hashedEntryURL(forResolvedPath: path)
        if FileManager.default.fileExists(atPath: hashed.path) {
            return hashed
        }
        for candidate in allEntryURLs() {
            if case .entry(let entry) = load(at: candidate), entry.sourcePath == path {
                return candidate
            }
        }
        return nil
    }

    private func allEntryURLs() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents.filter { $0.pathExtension == "json" }
    }

    private func load(at url: URL) -> Lookup {
        guard let data = try? Data(contentsOf: url) else { return .absent }
        if let entry = try? JSONDecoder().decode(Entry.self, from: data) {
            return .entry(entry)
        }
        if let artifact = try? JSONDecoder().decode(CodeArtifact.self, from: data) {
            return .legacyArtifact(artifact)
        }
        return .absent
    }
}

/// A stable, filename-safe digest of a path, used to key an analysis entry with no human-chosen
/// name.
private struct PathDigest {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    /// FNV-1a hash, seed-free so it's deterministic across the process's lifetime.
    var hex: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
