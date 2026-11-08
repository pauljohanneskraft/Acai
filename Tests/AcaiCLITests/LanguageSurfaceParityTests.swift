import Foundation
import Testing
import AcaiLibrary
@testable import AcaiCLI
@testable import AcaiMCP

/// The three surfaces that name languages must offer the same set, and that set must be the one
/// `AnalysisService.standard` actually parses. Before `LanguageNameCatalog` the CLI and the MCP server
/// each kept their own table, so registering a parser left both rejecting its language.
@Suite("Language surface parity")
struct LanguageSurfaceParityTests {

    private var registryNames: [String] {
        AnalysisService.standardParsers.map { $0.language.rawValue.lowercased() }
    }

    private var mcpSchemaNames: [String] {
        LanguageListArgument.languages.property["languages"]?
            .objectValue?["items"]?.objectValue?["enum"]?
            .arrayValue?.compactMap(\.stringValue) ?? []
    }

    @Test("The CLI, the MCP schema enum and the registry name the same languages")
    func surfacesAgree() {
        #expect(!registryNames.isEmpty)
        #expect(Set(LanguageOption.allValueStrings) == Set(registryNames))
        #expect(Set(mcpSchemaNames) == Set(registryNames))
    }

    /// Order is part of the contract: it is what `--help` and the schema enum print.
    @Test("Every surface lists the languages in registration order")
    func surfacesShareRegistrationOrder() {
        #expect(LanguageOption.allValueStrings == registryNames)
        #expect(mcpSchemaNames == registryNames)
    }

    @Test("Every registry language resolves on both surfaces, whatever its casing")
    func everyRegisteredLanguageResolves() throws {
        let resolver = SourceLanguageResolver()
        for parser in AnalysisService.standardParsers {
            let name = parser.language.rawValue
            for spelling in [name, name.lowercased(), name.uppercased()] {
                #expect(LanguageOption(argument: spelling)?.sourceLanguage == parser.language)
                #expect(resolver.language(named: spelling) == parser.language)
            }
        }
    }

    @Test("An unregistered language is rejected by both surfaces")
    func unregisteredLanguageIsRejected() {
        #expect(LanguageOption(argument: "cobol") == nil)
        #expect(SourceLanguageResolver().language(named: "cobol") == nil)
        #expect(!LanguageOption.allValueStrings.contains("cobol"))
    }
}
