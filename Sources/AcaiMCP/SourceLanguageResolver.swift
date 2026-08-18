import AcaiLibrary

/// Maps language names (`swift`, `kotlin`, `typescript`, …) onto the engine's `SourceLanguage` constants.
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

    /// Unknown names are dropped. An empty result means "no restriction", matching the contract
    /// `AnalysisService.analyzeProject` uses for an empty `allowedLanguages`.
    func resolve(names: [String]) -> [CodeArtifact.SourceLanguage] {
        names.compactMap { byName[$0.lowercased()] }
    }
}
