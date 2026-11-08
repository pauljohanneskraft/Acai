import ArgumentParser
import AcaiCore
import AcaiLibrary

/// A `--language` value: one of the languages `AnalysisService.standard` registers, named by its
/// lowercased `SourceLanguage.rawValue` and accepted case-insensitively.
struct LanguageOption: ExpressibleByArgument, Equatable {
    let sourceLanguage: CodeArtifact.SourceLanguage

    init?(argument: String) {
        guard let language = LanguageNameCatalog.standard.language(named: argument) else { return nil }
        sourceLanguage = language
    }

    static var allValueStrings: [String] { LanguageNameCatalog.standard.names }
}
