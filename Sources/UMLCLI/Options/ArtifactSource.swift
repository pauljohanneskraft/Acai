import ArgumentParser
import Foundation
import UMLCore
import UMLLibrary

/// The shared `--from` / `--source` / `--language` inputs that select the `CodeArtifact` a command
/// operates on, plus the loading and validation logic. `@OptionGroup`-ed into each command so the
/// flags, their mutual-exclusion rule, the stored-vs-analyze dispatch, and parse-warning surfacing
/// live in one place.
struct ArtifactSource: ParsableArguments {
    @Option(name: .long, help: "Name of a stored analysis or path to a .json file.")
    var from: String?

    @Option(name: .long, help: "Path to a source directory to analyze on the fly.")
    var source: String?

    @Option(name: .long, help: ArgumentHelp(
        "Limit analysis to one or more languages when using --source" +
        " (\(LanguageOption.allValuesList))." +
        " Repeat the flag for multiple: --language kotlin --language java."
    ))
    var language: [LanguageOption] = []

    /// Validates that exactly one of `--from` / `--source` is provided. Call from the command's
    /// `validate()` (ArgumentParser only invokes `validate()` on the root command, not on groups).
    func validate() throws {
        if from == nil && source == nil {
            throw ValidationError("Either --from or --source must be specified.")
        }
        if from != nil && source != nil {
            throw ValidationError("Specify either --from or --source, not both.")
        }
    }

    /// Loads the selected artifact: a stored analysis (`--from`, a `.json` path or a stored name) or
    /// a freshly analyzed source directory (`--source`). Parse warnings are surfaced to stderr in
    /// both cases so a partial diagram is never mistaken for a complete one.
    func resolve() throws -> CodeArtifact {
        try Self.resolve(from: from, source: source, language: language)
    }

    /// The shared `--from` / `--source` resolution used by `resolve()` and by commands that need to
    /// load more than one artifact (e.g. `diff`, which loads an old and a new side). Parse warnings
    /// are surfaced to stderr so a partial artifact is never mistaken for a complete one.
    static func resolve(from: String?, source: String?, language: [LanguageOption]) throws -> CodeArtifact {
        let artifact: CodeArtifact
        if let from {
            artifact = try loadStored(from)
        } else if let source {
            let url = URL(fileURLWithPath: source).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("Source directory does not exist: \(source)")
            }
            artifact = try AnalysisService.standard.analyzeProject(
                at: url, allowedLanguages: language.map(\.sourceLanguage)
            )
        } else {
            throw ValidationError("Either --from or --source must be specified.")
        }
        artifact.warnIfParseErrors()
        return artifact
    }

    /// Loads a stored artifact: a `.json` file path, or the name of a stored analysis. A file
    /// produced by `analyze`/`store` is already enriched. A `DecodingError` means the stored file
    /// predates a schema change (e.g. the now-required `accessLevel`); it is reported as "regenerate
    /// it", the CLI equivalent of treating the codebase as not indexed, rather than a raw decode dump.
    static func loadStored(_ value: String) throws -> CodeArtifact {
        let directURL = URL(fileURLWithPath: value)
        let url: URL
        if FileManager.default.fileExists(atPath: directURL.path) {
            url = directURL
        } else {
            let storedURL = UMLConstants.standard.analysisDirectory.appendingPathComponent("\(value).json")
            guard FileManager.default.fileExists(atPath: storedURL.path) else {
                throw ValidationError(
                    "Could not find analysis '\(value)'. "
                    + "Provide a path to a .json file or the name of a stored analysis."
                )
            }
            url = storedURL
        }
        do {
            return try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: url))
        } catch is DecodingError {
            throw ValidationError(
                "Stored analysis '\(value)' was produced by an older UML version and can no longer be read. "
                + "Re-run `uml analyze` / `uml store` to regenerate it."
            )
        }
    }
}
