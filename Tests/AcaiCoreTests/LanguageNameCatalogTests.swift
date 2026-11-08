import Foundation
import Testing
import AcaiCore

private struct NamedParser: CodeParser {
    let language: CodeArtifact.SourceLanguage
    var fileExtensions: [String] { [] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    init(_ rawValue: String) { language = CodeArtifact.SourceLanguage(rawValue: rawValue) }

    func parse(source: String, fileName: String) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]))
    }
}

@Suite("Language name catalog")
struct LanguageNameCatalogTests {

    @Test("Names are the lowercased raw values, in registration order")
    func namesFollowRegistrationOrder() {
        let catalog = LanguageNameCatalog(
            parsers: [NamedParser("swift"), NamedParser("typeScript"), NamedParser("c")])
        #expect(catalog.names == ["swift", "typescript", "c"])
        #expect(catalog.namesList == "swift, typescript, c")
    }

    /// The name is lowercased; the language it resolves to keeps the raw value the parser reports.
    @Test("Lookup ignores case and rejects an unregistered name")
    func lookupIgnoresCase() {
        let catalog = LanguageNameCatalog(parsers: [NamedParser("typeScript")])
        for spelling in ["typeScript", "typescript", "TYPESCRIPT"] {
            #expect(catalog.language(named: spelling)?.rawValue == "typeScript")
        }
        #expect(catalog.language(named: "cobol") == nil)
    }

    /// Two parsers may report one language — a dialect routed by file content — and help text must
    /// not offer its name twice.
    @Test("A language two parsers report is named once")
    func duplicateLanguageIsNamedOnce() {
        let catalog = LanguageNameCatalog(
            parsers: [NamedParser("c"), NamedParser("cpp"), NamedParser("c")])
        #expect(catalog.names == ["c", "cpp"])
    }

    @Test("An empty parser set names nothing")
    func emptyParserSetNamesNothing() {
        let catalog = LanguageNameCatalog(parsers: [])
        #expect(catalog.names.isEmpty)
        #expect(catalog.namesList.isEmpty)
        #expect(catalog.language(named: "swift") == nil)
    }
}
