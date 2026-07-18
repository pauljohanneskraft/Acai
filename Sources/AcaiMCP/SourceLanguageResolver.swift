import AcaiLibrary

/// Maps the `--language` names a user types (`swift`, `kotlin`, `typescript`, …) onto the engine's
/// `SourceLanguage` constants. A value you instantiate (`SourceLanguageResolver().resolve(names:)`);
/// the constants themselves live in the language plugins and reach here via `AcaiLibrary`'s re-exports,
/// so this entry point still names no language of its own beyond the user-facing spelling table.
struct SourceLanguageResolver: Sendable {
    private let byName: [String: CodeArtifact.SourceLanguage] = [
        "swift": .swift,
        "kotlin": .kotlin,
        "java": .java,
        "typescript": .typeScript,
        "javascript": .javaScript,
        "dart": .dart,
        "python": .python,
        "c": .c,
        "cpp": .cpp
    ]

    /// The requested languages, unknown names dropped. An empty result means "no restriction" — the
    /// same contract `AnalysisService.analyzeProject` uses for an empty `allowedLanguages`.
    func resolve(names: [String]) -> [CodeArtifact.SourceLanguage] {
        names.compactMap { byName[$0.lowercased()] }
    }
}
