import Foundation
import Testing
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender
@testable import AcaiApp

/// `CodeElementReference.resolutions(in:existingDiagrams:)` (B28): one shared resolution
/// mechanism every "Open in…" surface eventually calls into. Layer 0, per the resolution-table
/// unit tests the backlog item itself calls for — no UI, no live app state.
@Suite("CodeElementReference resolution")
struct CodeElementReferenceResolutionTests {

    private func type(
        id: String, name: String, kind: TypeKind = .class, members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(id: id, name: name, qualifiedName: id, kind: kind, accessLevel: .public, members: members)
    }

    private func artifact(types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]), types: types)
    }

    private func diagram(_ content: GeneratedDiagram.Content) -> GeneratedDiagram {
        GeneratedDiagram(name: "D", content: content, codebaseID: UUID())
    }

    // MARK: - Type

    @Test("A type resolves to Class Diagram, Call Graph, and Package Diagram, all offering to create")
    func typeResolvesToThreeDiagramTypesByDefault() {
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        let resolutions = CodeElementReference.type(id: "Foo").resolutions(in: art, existingDiagrams: [])

        let byType = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.diagramType, $0.target) })
        #expect(Set(byType.keys) == [.classDiagram, .callGraph, .packageDiagram])

        guard case .create(.classDiagram(let config)) = byType[.classDiagram] else {
            Issue.record("expected a class-diagram creation target")
            return
        }
        #expect(config.focus?.rootTypeName == "Foo")

        guard case .create(.callGraph(.type("Foo"))) = byType[.callGraph] else {
            Issue.record("expected a call-graph creation target scoped to Foo")
            return
        }

        guard case .create(.packageDiagram) = byType[.packageDiagram] else {
            Issue.record("expected a package-diagram creation target")
            return
        }
    }

    @Test("A type with an enum-typed property also offers State Diagram")
    func typeWithEnumPropertyOffersStateDiagram() {
        let art = artifact(types: [
            type(id: "Status", name: "Status", kind: .enum),
            type(id: "Order", name: "Order", members: [
                Member(name: "status", kind: .property, accessLevel: .public, type: .init(name: "Status"))
            ])
        ])

        let resolutions = CodeElementReference.type(id: "Order").resolutions(in: art, existingDiagrams: [])
        let stateTarget = resolutions.first { $0.diagramType == .stateDiagram }?.target

        guard case .create(.stateDiagram(let config)) = stateTarget else {
            Issue.record("expected a state-diagram creation target")
            return
        }
        #expect(config?.typeName == "Order")
        #expect(config?.variableName == "status")
    }

    @Test("A type with no enum-typed property does not offer State Diagram")
    func typeWithoutEnumPropertyOmitsStateDiagram() {
        let art = artifact(types: [
            type(id: "Order", name: "Order", members: [
                Member(name: "total", kind: .property, accessLevel: .public, type: .init(name: "Int"))
            ])
        ])
        let resolutions = CodeElementReference.type(id: "Order").resolutions(in: art, existingDiagrams: [])
        #expect(!resolutions.contains { $0.diagramType == .stateDiagram })
    }

    @Test("An unknown type id resolves to nothing")
    func unknownTypeResolvesEmpty() {
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        #expect(CodeElementReference.type(id: "Ghost").resolutions(in: art, existingDiagrams: []).isEmpty)
    }

    @Test("An existing focused Class Diagram is reused over creating a new one")
    func typeReusesExistingFocusedClassDiagram() {
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        var config = ClassDiagramConfiguration()
        config.focus = .init(rootTypeName: "Foo")
        let existing = diagram(.classDiagram(config))

        let resolutions = CodeElementReference.type(id: "Foo").resolutions(in: art, existingDiagrams: [existing])
        let classTarget = resolutions.first { $0.diagramType == .classDiagram }?.target
        #expect(classTarget == .existing(existing.id))
    }

    @Test("An existing unfocused Class Diagram is reused when no exactly-focused one exists")
    func typeReusesExistingUnfocusedClassDiagram() {
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        let existing = diagram(.classDiagram(.init()))

        let resolutions = CodeElementReference.type(id: "Foo").resolutions(in: art, existingDiagrams: [existing])
        let classTarget = resolutions.first { $0.diagramType == .classDiagram }?.target
        #expect(classTarget == .existing(existing.id))
    }

    @Test("An existing whole-codebase Call Graph is reused for a type-scoped request")
    func typeReusesWholeCodebaseCallGraph() {
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        let existing = diagram(.callGraph(.wholeCodebase))

        let resolutions = CodeElementReference.type(id: "Foo").resolutions(in: art, existingDiagrams: [existing])
        let callGraphTarget = resolutions.first { $0.diagramType == .callGraph }?.target
        #expect(callGraphTarget == .existing(existing.id))
    }

    // MARK: - Method

    @Test("A method on a type resolves to Sequence Diagram and a type-scoped Call Graph")
    func methodOnTypeResolvesSequenceAndScopedCallGraph() {
        let resolutions = CodeElementReference
            .method(typeName: "Foo", methodName: "bar")
            .resolutions(in: artifact(types: []), existingDiagrams: [])

        let byType = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.diagramType, $0.target) })
        #expect(Set(byType.keys) == [.sequenceDiagram, .callGraph])

        guard case .create(.sequenceDiagram(let config)) = byType[.sequenceDiagram] else {
            Issue.record("expected a sequence-diagram creation target")
            return
        }
        #expect(config.entryTypeName == "Foo")
        #expect(config.entryMethodName == "bar")

        guard case .create(.callGraph(.type("Foo"))) = byType[.callGraph] else {
            Issue.record("expected a call-graph creation target scoped to Foo")
            return
        }
    }

    @Test("A free function (no owning type) scopes its Call Graph to the whole codebase")
    func freeFunctionScopesWholeCodebaseCallGraph() {
        let resolutions = CodeElementReference
            .method(typeName: nil, methodName: "main")
            .resolutions(in: artifact(types: []), existingDiagrams: [])

        guard case .create(.sequenceDiagram(let config)) =
            resolutions.first(where: { $0.diagramType == .sequenceDiagram })?.target else {
            Issue.record("expected a sequence-diagram creation target")
            return
        }
        #expect(config.entryTypeName.isEmpty)
        #expect(config.entryMethodName == "main")

        guard case .create(.callGraph(.wholeCodebase)) =
            resolutions.first(where: { $0.diagramType == .callGraph })?.target else {
            Issue.record("expected a whole-codebase call-graph creation target")
            return
        }
    }

    // MARK: - Module

    @Test("A module resolves only to Package Diagram (Class Diagram's module filter doesn't exist yet)")
    func moduleResolvesOnlyToPackageDiagram() {
        let resolutions = CodeElementReference
            .module(name: "AcaiCore")
            .resolutions(in: artifact(types: []), existingDiagrams: [])
        #expect(resolutions.map(\.diagramType) == [.packageDiagram])
    }

    // MARK: - Relationship

    @Test("A relationship resolves to a Class Diagram focused on its source")
    func relationshipResolvesToFocusedClassDiagram() {
        let resolutions = CodeElementReference
            .relationship(source: "Foo", target: "Bar", kind: .dependency)
            .resolutions(in: artifact(types: []), existingDiagrams: [])

        #expect(resolutions.map(\.diagramType) == [.classDiagram])
        guard case .create(.classDiagram(let config)) = resolutions.first?.target else {
            Issue.record("expected a class-diagram creation target")
            return
        }
        #expect(config.focus?.rootTypeName == "Foo")
    }

    // MARK: - Violation → CodeElementReference

    @Test("An edge-shaped violation subject resolves to a relationship")
    func edgeViolationResolvesToRelationship() {
        let violation = Violation(
            ruleKind: "forbidden-dependency", message: "", subject: "Foo→Bar",
            detail: ["kind": "dependency"]
        )
        #expect(
            violation.codeElementReference(in: artifact(types: [])) ==
            .relationship(source: "Foo", target: "Bar", kind: .dependency)
        )
    }

    @Test("A cycle violation whose first member is a known type resolves to that type")
    func cycleViolationWithTypeMemberResolvesToType() {
        let art = artifact(types: [type(id: "Foo", name: "Foo"), type(id: "Bar", name: "Bar")])
        let violation = Violation(
            ruleKind: "cycle", message: "", subject: "Foo,Bar", detail: ["scope": "types"]
        )
        #expect(violation.codeElementReference(in: art) == .type(id: "Foo"))
    }

    @Test("A cycle violation whose first member is not a known type resolves to a module")
    func cycleViolationWithModuleMemberResolvesToModule() {
        let violation = Violation(
            ruleKind: "cycle", message: "", subject: "ModuleA,ModuleB", detail: ["scope": "modules"]
        )
        #expect(violation.codeElementReference(in: artifact(types: [])) == .module(name: "ModuleA"))
    }

    @Test("A budget violation subject matching a known type resolves to that type")
    func budgetViolationWithTypeSubjectResolvesToType() {
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        let violation = Violation(ruleKind: "budget", message: "", subject: "Foo")
        #expect(violation.codeElementReference(in: art) == .type(id: "Foo"))
    }

    @Test("A budget violation subject matching no known type resolves to a module")
    func budgetViolationWithModuleSubjectResolvesToModule() {
        let violation = Violation(ruleKind: "budget", message: "", subject: "AcaiCore")
        #expect(violation.codeElementReference(in: artifact(types: [])) == .module(name: "AcaiCore"))
    }
}
