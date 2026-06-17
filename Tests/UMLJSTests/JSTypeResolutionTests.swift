import Testing
@testable import UMLCore
@testable import UMLJS

@Suite("TypeScript Type Resolution")
struct JSTypeResolutionTests {
    let parser = JSCodeParser(isTypeScript: true)

    /// Inherited-type names resolve to qualified ids via the language-agnostic `enriched()` pass.
    /// A `namespace` makes the canonical id qualified (`Zoo.Animal`) while the `extends Animal`
    /// reference stays raw, so the rewrite is observable — a genuine regression guard for the
    /// enrichment path (and for TS namespaced-id qualification).
    @Test func inheritedTypeNamesResolveToQualifiedIdAfterEnrichment() {
        let source = """
        namespace Zoo {
            class Animal {}
            class Dog extends Animal {}
        }
        """
        // Before enrichment the supertype is the raw, unqualified name.
        let raw = parser.parse(source: source, fileName: "zoo.ts").flattened()
        #expect(raw.first { $0.name == "Dog" }?.inheritedTypes.first?.name == "Animal")

        let enriched = parser.parse(source: source, fileName: "zoo.ts")
            .enriched(configuration: parser.configuration).flattened()
        #expect(enriched.first { $0.name == "Animal" }?.id == "Zoo.Animal")
        #expect(enriched.first { $0.name == "Dog" }?.inheritedTypes.first?.name == "Zoo.Animal")
    }
}
