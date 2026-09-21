import ArgumentParser
import Foundation
import AcaiCore
import AcaiLibrary

/// The shared `--from` / `--source` / `--language` inputs that select the `CodeArtifact` a command
/// operates on, plus the loading and validation logic. `@OptionGroup`-ed into each command.
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
    /// `validate()` — ArgumentParser doesn't invoke `validate()` on option groups.
    func validate() throws {
        if from == nil && source == nil {
            throw ValidationError("Either --from or --source must be specified.")
        }
        if from != nil && source != nil {
            throw ValidationError("Specify either --from or --source, not both.")
        }
    }

    func resolve() async throws -> CodeArtifact {
        try await Self.resolve(from: from, source: source, language: language)
    }

    /// Also used by commands loading more than one artifact (e.g. `diff`'s old/new sides).
    static func resolve(from: String?, source: String?, language: [LanguageOption]) async throws -> CodeArtifact {
        let artifact: CodeArtifact
        if let from {
            artifact = try loadStored(from)
        } else if let source {
            let url = URL(fileURLWithPath: source).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("Source directory does not exist: \(source)")
            }
            artifact = try await AnalysisService.standard.analyzeProject(
                at: url, allowedLanguages: language.map(\.sourceLanguage)
            )
        } else {
            throw ValidationError("Either --from or --source must be specified.")
        }
        artifact.warnIfParseErrors()
        return artifact
    }

    /// Resolves `--from` against, in order: a path to a `.json` artifact file (today's behavior,
    /// kept as-is), a path to a source directory that has a stored entry, and the name of a stored
    /// analysis. A `DecodingError` on a direct file, or a named entry that exists but fails to
    /// decode as either the current or the legacy shape, is reported as "regenerate it" rather
    /// than a raw decode dump.
    static func loadStored(_ value: String) throws -> CodeArtifact {
        let directURL = URL(fileURLWithPath: value)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directURL.path, isDirectory: &isDirectory)

        if exists, !isDirectory.boolValue {
            do {
                return try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: directURL))
            } catch is DecodingError {
                throw ValidationError(
                    "Stored analysis '\(value)' was produced by an older Açaí version and can no longer be read. "
                    + "Re-run `acai analyze` / `acai store` to regenerate it."
                )
            }
        }

        let store = AnalysisStore.standard

        if exists, isDirectory.boolValue {
            let resolvedPath = directURL.standardizedFileURL.resolvingSymlinksInPath().path
            switch store.lookup(forResolvedPath: resolvedPath) {
            case .entry(let entry):
                return entry.artifact
            case .legacyArtifact(let artifact):
                return artifact
            case .absent:
                throw ValidationError(
                    "No stored analysis found for '\(value)'. Run `acai store` or pass --source to analyze it."
                )
            }
        }

        switch store.lookup(named: value) {
        case .entry(let entry):
            return entry.artifact
        case .legacyArtifact(let artifact):
            return artifact
        case .absent:
            guard FileManager.default.fileExists(atPath: store.url(forName: value).path) else {
                throw ValidationError(
                    "Could not find analysis '\(value)'. "
                    + "Provide a path to a .json file or the name of a stored analysis."
                )
            }
            throw ValidationError(
                "Stored analysis '\(value)' was produced by an older Açaí version and can no longer be read. "
                + "Re-run `acai analyze` / `acai store` to regenerate it."
            )
        }
    }
}
