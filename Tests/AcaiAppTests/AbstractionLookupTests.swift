import Testing
import AcaiCore
@testable import AcaiApp

/// Interface-resolution lookups must accept Swift existential spellings: traces name
/// participants after declared receiver types, so `any P` / `some P` have to resolve to the
/// protocol `P` (while the `typeMapping` key stays the raw spelling).
@Suite("Abstraction Lookup")
struct AbstractionLookupTests {

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "P", name: "P", qualifiedName: "P", kind: .protocol, accessLevel: .public),
                TypeDeclaration(id: "Impl", name: "Impl", qualifiedName: "Impl", kind: .struct, accessLevel: .public),
                TypeDeclaration(id: "Other", name: "Other", qualifiedName: "Other", kind: .class, accessLevel: .public)
            ],
            relationships: [
                Relationship(kind: .conformance, source: "Impl", target: "P")
            ]
        )
    }

    @Test("Existential and plain spellings resolve to the protocol")
    func existentialSpellingsResolve() {
        let art = artifact()
        #expect(art.abstractionType(named: "P")?.id == "P")
        #expect(art.abstractionType(named: "any P")?.id == "P")
        #expect(art.abstractionType(named: "some P")?.id == "P")
    }

    @Test("Non-abstractions and unknown names resolve to nil")
    func nonAbstractionsAreNil() {
        let art = artifact()
        #expect(art.abstractionType(named: "Impl") == nil)   // concrete type
        #expect(art.abstractionType(named: "Nope") == nil)   // unknown
        #expect(art.abstractionType(named: "any Nope") == nil)
    }

    @Test("Conformers are found through existential spellings")
    func conformersThroughExistential() {
        let art = artifact()
        #expect(art.conformerNames(ofAbstractionNamed: "any P") == ["Impl"])
        #expect(art.conformerNames(ofAbstractionNamed: "P") == ["Impl"])
        #expect(art.conformerNames(ofAbstractionNamed: "Impl").isEmpty)
    }
}
