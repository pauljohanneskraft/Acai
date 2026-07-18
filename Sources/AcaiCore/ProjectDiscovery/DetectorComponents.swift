import Foundation

// Reusable, language-agnostic building blocks that build-system detectors compose. Each is a small
// value with instance methods (never a static-namespace) so a detector holds the ones it needs and
// supplies only its own declarative config (indicator file names, conventional source dir, source
// extensions). Keeping these here — not in any language plugin — means they name no language.

/// The set of languages a discovery pass asked for. An empty request means "all languages this
/// detector can offer"; a non-empty request restricts the detector to the listed languages. Wraps
/// the `requestedLanguages.isEmpty || requestedLanguages.contains(_)` test every detector repeated.
public struct LanguageRequest: Sendable {
    private let requested: [CodeArtifact.SourceLanguage]

    public init(_ requested: [CodeArtifact.SourceLanguage]) {
        self.requested = requested
    }

    /// Whether `language` should be discovered under this request.
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

    /// Whether any indicator file exists directly under `root`.
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

    /// `[preferredSubdirectory]` when it exists under `root`, otherwise `[root]`.
    public func directories(in root: URL) -> [URL] {
        let preferred = root.appendingPathComponent(preferredSubdirectory)
        return FileManager.default.fileExists(atPath: preferred.path) ? [preferred] : [root]
    }
}

/// Tests whether source files of a given language actually exist, so a detector reports a language
/// only when there is something to parse. Carries the language's file extensions and the directories
/// to skip while scanning.
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

    /// Whether at least one matching file exists anywhere under `directory`.
    public func exist(in directory: URL) -> Bool {
        !FileManager.default.fileURLs(
            in: directory, withExtensions: extensions, excludingDirectories: excludedDirectories
        ).isEmpty
    }

    /// Whether at least one matching file exists under any of `directories`.
    public func exist(inAnyOf directories: [URL]) -> Bool {
        directories.contains { exist(in: $0) }
    }
}
