import Testing
@testable import UMLCore
@testable import UMLDart

@Suite("Dart: Type Resolution")
struct DartTypeResolutionTests {
    let parser = DartCodeParser()

    /// Inherited-type names are resolved to qualified ids by the language-agnostic `enriched()`
    /// pipeline (not the per-extractor pass, which Dart doesn't run), so the app's inspector
    /// views show consistent names. Uses a `library` directive so ids are namespaced and the
    /// resolution is observable.
    @Test func inheritedTypeNamesResolveAfterEnrichment() {
        let source = """
        library zoo;

        class Animal {
            String name;
        }

        class Dog extends Animal {
            String breed;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Animals.dart")
        let dogRaw = artifact.types.first { $0.name == "Dog" }
        // Before enrichment Dart leaves the supertype name as written.
        #expect(dogRaw?.inheritedTypes.first?.name == "Animal")

        let enriched = artifact.enriched(configuration: parser.configuration)
        let animal = enriched.types.first { $0.name == "Animal" }
        let dog = enriched.types.first { $0.name == "Dog" }
        #expect(animal?.id == "zoo.Animal")
        #expect(dog?.inheritedTypes.first?.name == "zoo.Animal")
    }
}
