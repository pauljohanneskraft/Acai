import Foundation
import Testing
import UMLCore

// Acceptance test for issue #69: a consumer can add a brand-new language entirely from the outside
// — its own `SourceLanguage` value, parser, `LanguageConfiguration`, and `BuildSystemDetector` — and
// the agnostic engine honours all of it. Nothing in UMLCore (or any other agnostic target) is
// touched: everything below is declared here, in the "external" test module.

extension CodeArtifact.SourceLanguage {
    /// An entirely new language, defined outside the package — impossible with a closed enum.
    fileprivate static let fake = CodeArtifact.SourceLanguage(rawValue: "fake")
}

/// A made-up language whose quirks (primitives, collections, generated-code filter, build dirs)
/// live wholly in its configuration.
private struct FakeLangParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .fake }
    var fileExtensions: [String] { ["fk"] }

    var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: ["FakeInt", "FakeString"],
            collectionTypeNames: ["FakeList"],
            annotationStereotypes: ["fakeentity": "entity"],
            generatedCodeFilter: GeneratedCodeFilter(
                displayName: "Fake Generated Types",
                explanation: "Hides .gen.fk files and $$-prefixed types.",
                fileSuffixes: [".gen.fk"],
                typeNamePatterns: [NamePattern(prefix: "$$")]
            ),
            excludedDirectories: ["fake_modules"]
        )
    }

    func parse(source: String, fileName: String) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .fake, filePaths: [fileName]))
    }
}

private func ref(_ name: String) -> TypeReference { TypeReference(name: name) }

@Suite("External language plugin")
struct ExternalLanguagePluginTests {

    private func widget(properties: [Member]) -> TypeDeclaration {
        TypeDeclaration(id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class, members: properties)
    }

    private func property(_ name: String, type: String) -> Member {
        Member(name: name, kind: .property, type: ref(type))
    }

    @Test("enrichment classifies type names using the external language's configuration")
    func enrichmentHonoursExternalClassification() {
        let parser = FakeLangParser()
        let widget = widget(properties: [
            property("count", type: "FakeInt"),       // external primitive — no edge
            property("items", type: "FakeList"),      // external collection — no edge
            property("engine", type: "Engine")        // real type — composition edge
        ])
        let engine = TypeDeclaration(id: "Engine", name: "Engine", qualifiedName: "Engine", kind: .class)
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .fake), types: [widget, engine]
        )

        let enriched = artifact.enriched(configuration: parser.configuration)

        let targets = Set(enriched.relationships.map(\.target))
        #expect(targets.contains("Engine"))          // real type became an edge
        #expect(!targets.contains("FakeInt"))        // external primitive was classified out
        #expect(!targets.contains("FakeList"))       // external collection was classified out
    }

    @Test("generated-code filtering uses the external language's filter")
    func generatedFilteringHonoursExternalFilter() throws {
        let parser = FakeLangParser()
        let real = TypeDeclaration(id: "Real", name: "Real", qualifiedName: "Real", kind: .class)
        let byName = TypeDeclaration(id: "$$Gen", name: "$$Gen", qualifiedName: "$$Gen", kind: .class)
        let byFile = TypeDeclaration(
            id: "Model", name: "Model", qualifiedName: "Model", kind: .class,
            location: SourceLocation(filePath: "lib/model.gen.fk", line: 1, column: 1)
        )
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .fake), types: [real, byName, byFile])

        let filter = try #require(parser.configuration.generatedCodeFilter)
        let filtered = artifact.filteringGeneratedTypes(using: filter)

        let names = Set(filtered.types.map(\.name))
        #expect(names == ["Real"])                    // both generated types removed
    }

    @Test("a registry built from external parsers resolves them, and returns nil for unknown")
    func registryResolvesExternalLanguage() {
        let registry = LanguageRegistry(parsers: [FakeLangParser()])
        #expect(registry.configuration(for: .fake)?.primitiveTypeNames.contains("FakeInt") == true)
        #expect(registry.configuration(for: CodeArtifact.SourceLanguage(rawValue: "unknown")) == nil)
        #expect(registry.excludedDirectories.contains("fake_modules"))
    }

    @Test("AnalysisService composes purely from the external parser")
    func analysisServiceComposesExternalParser() {
        let service = AnalysisService(parsers: [FakeLangParser()])
        #expect(service.parser(for: .fake) != nil)
        #expect(service.registry.configuration(for: .fake) != nil)
    }
}
