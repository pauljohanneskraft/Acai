import Testing
@testable import UMLCore
@testable import UMLJS

@Suite("TypeScript Type Resolution")
struct JSTypeResolutionTests {
    let parser = JSCodeParser(isTypeScript: true)

    /// After the language-agnostic `enriched()` pass, a class's inherited-type names reference
    /// the canonical id of same-codebase types — the same property Kotlin/Java get from their
    /// per-extractor resolution. (TS ids are flat, so this is already consistent; the test guards
    /// against regressions and documents that JS/TS now flow through the shared resolution.)
    @Test func inheritedTypeNamesReferenceCanonicalIdAfterEnrichment() {
        let source = """
        class Animal {}
        class Dog extends Animal {}
        """
        let enriched = parser.parse(source: source, fileName: "animals.ts").enriched()
        let animal = enriched.types.first { $0.name == "Animal" }
        let dog = enriched.types.first { $0.name == "Dog" }
        #expect(animal != nil)
        #expect(dog?.inheritedTypes.first?.name == animal?.id)
    }
}
