import Foundation

// Reusable, language-agnostic building blocks that build-system detectors compose. Keeping these
// here — not in any language plugin — means they name no language.

/// An empty request means "all languages this detector can offer"; a non-empty request restricts
/// the detector to the listed languages.
public struct LanguageRequest: Sendable {
    private let requested: [CodeArtifact.SourceLanguage]

    public init(_ requested: [CodeArtifact.SourceLanguage]) {
        self.requested = requested
    }

    public func wants(_ language: CodeArtifact.SourceLanguage) -> Bool {
        requested.isEmpty || requested.contains(language)
    }

    /// Whether the caller named `language` explicitly (as opposed to an unrestricted "all" request) —
    /// used where an explicit request overrides a heuristic (e.g. adding JS to a TS project).
    public func explicitlyWants(_ language: CodeArtifact.SourceLanguage) -> Bool {
        requested.contains(language)
    }
}

/// Recognises a build system by the presence of any one of a set of root-relative indicator files
/// (e.g. `Package.swift`, or any of Gradle's `build.gradle{,.kts}` / `settings.gradle{,.kts}`).
public struct IndicatorFiles: Sendable {
    private let names: [String]

    public init(_ names: [String]) {
        self.names = names
    }

    public func present(at root: URL) -> Bool {
        names.contains {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }
}

/// Resolves a build system's source directories using the "prefer the conventional subdirectory,
/// else fall back to the project root" convention shared by SwiftPM (`Sources`), Node/Python (`src`),
/// and Flutter (`lib`).
public struct SourceDirectoryProbe: Sendable {
    private let preferredSubdirectory: String

    public init(preferring preferredSubdirectory: String) {
        self.preferredSubdirectory = preferredSubdirectory
    }

    public func directories(in root: URL) -> [URL] {
        let preferred = root.appendingPathComponent(preferredSubdirectory)
        return FileManager.default.fileExists(atPath: preferred.path) ? [preferred] : [root]
    }
}

/// Tests whether source files of a given language actually exist, so a detector reports a language
/// only when there is something to parse.
public struct SourceFilePresence: Sendable {
    private let extensions: Set<String>
    private let excludedDirectories: Set<String>

    public init(
        extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> =
            AcaiConstants.standard.defaultExcludedSourceDirectories
    ) {
        self.extensions = extensions
        self.excludedDirectories = excludedDirectories
    }

    public func exist(in directory: URL) -> Bool {
        !FileManager.default.fileExtensionsPresent(
            in: directory, among: extensions, excludingDirectories: excludedDirectories
        ).isEmpty
    }

    public func exist(inAnyOf directories: [URL]) -> Bool {
        directories.contains { exist(in: $0) }
    }
}

/// Expands one of a manifest's directory patterns — `packages/*`, `apps/**`, `libs/*-core`, or a
/// plain `tools/cli` — into the directories that exist under a root. `*` and `?` match within a
/// single path component; `**` spans any number of them, including none.
///
/// Symlinked directories are never descended into, so a link pointing at one of its own ancestors
/// cannot turn a `**` into an unbounded walk.
public struct DirectoryGlob: Sendable {
    private let segments: [String]
    private let excludedDirectories: Set<String>

    public init(
        _ pattern: String,
        excludingDirectories excludedDirectories: Set<String> =
            AcaiConstants.standard.defaultExcludedSourceDirectories
    ) {
        segments = pattern.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "." }
        self.excludedDirectories = excludedDirectories
    }

    public func directories(in root: URL) -> [URL] {
        matches(of: segments[...], in: root.standardizedFileURL).removingDuplicates { $0.path }
    }

    private func matches(of segments: ArraySlice<String>, in directory: URL) -> [URL] {
        guard let segment = segments.first else { return [directory] }
        let rest = segments.dropFirst()
        if segment == "**" {
            return matches(of: rest, in: directory)
                + subdirectories(of: directory).flatMap { matches(of: segments, in: $0) }
        }
        guard segment.contains("*") || segment.contains("?") else {
            let child = directory.appendingPathComponent(segment).standardizedFileURL
            return child.isReachableDirectory ? matches(of: rest, in: child) : []
        }
        let glob = Glob(segment)
        return subdirectories(of: directory)
            .filter { glob.matches($0.lastPathComponent) }
            .flatMap { matches(of: rest, in: $0) }
    }

    private func subdirectories(of directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { !excludedDirectories.contains($0.lastPathComponent) && $0.isReachableDirectory }
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
    }
}

extension URL {
    /// A directory that can be walked: a real directory, not a symlink to one.
    fileprivate var isReachableDirectory: Bool {
        let values = try? resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
}
