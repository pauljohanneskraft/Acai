import ArgumentParser
import AcaiCore
import AcaiLibrary

struct LanguageOption: ExpressibleByArgument, Equatable {
    let sourceLanguage: CodeArtifact.SourceLanguage

    init?(argument: String) {
        guard let language = LanguageNameCatalog.standard.language(named: argument) else { return nil }
        sourceLanguage = language
    }

    static var allValueStrings: [String] { LanguageNameCatalog.standard.names }
}
