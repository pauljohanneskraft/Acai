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
        !FileManager.default.fileURLs(
            in: directory, withExtensions: extensions, excludingDirectories: excludedDirectories
        ).isEmpty
    }

    public func exist(inAnyOf directories: [URL]) -> Bool {
        directories.contains { exist(in: $0) }
    }
}
