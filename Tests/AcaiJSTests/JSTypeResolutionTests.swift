import Testing
@testable import AcaiCore
@testable import AcaiJS

@Suite("TypeScript Type Resolution")
struct JSTypeResolutionTests {
    let parser = JSCodeParser(isTypeScript: true)

    /// Inherited-type names resolve to qualified ids via the language-agnostic `enriched()` pass.
    /// A `namespace` makes the canonical id qualified (`Zoo.Animal`) while the `extends Animal`
    /// reference stays raw, so the rewrite is observable.
    @Test func inheritedTypeNamesResolveToQualifiedIdAfterEnrichment() {
        let source = """
        namespace Zoo {
            class Animal {}
            class Dog extends Animal {}
        }
        """
        let raw = parser.parse(source: source, fileName: "zoo.ts").flattened()
        #expect(raw.first { $0.name == "Dog" }?.inheritedTypes.first?.name == "Animal")

        let enriched = parser.parse(source: source, fileName: "zoo.ts")
            .enriched(configuration: parser.configuration).flattened()
        #expect(enriched.first { $0.name == "Animal" }?.id == "Zoo.Animal")
        #expect(enriched.first { $0.name == "Dog" }?.inheritedTypes.first?.name == "Zoo.Animal")
    }

    /// The `constraint` node spans the whole `extends Error` clause, keyword included; the
    /// constraint must resolve to the bound type (`Error`), not to that literal text.
    @Test func genericConstraintResolvesToTheBoundTypeNotTheExtendsClause() {
        let source = """
        interface Sink<T extends Error> {}
        """
        let artifact = parser.parse(source: source, fileName: "sink.ts")
        let sink = artifact.types.first { $0.name == "Sink" }
        #expect(sink?.genericParameters.first?.constraints.first?.type.name == "Error")
    }

    /// A multi-bound constraint (`T extends A & B`) still drops the `extends` keyword; the bound
    /// resolves through the existing intersection-type handling rather than taking raw clause text.
    @Test func multiBoundGenericConstraintDropsTheExtendsKeyword() {
        let source = """
        interface Multi<T extends A & B> {}
        """
        let artifact = parser.parse(source: source, fileName: "multi.ts")
        let multi = artifact.types.first { $0.name == "Multi" }
        #expect(multi?.genericParameters.first?.constraints.first?.type.name == "A & B")
    }
}
