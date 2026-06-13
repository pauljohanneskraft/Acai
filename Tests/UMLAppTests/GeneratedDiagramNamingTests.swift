import Foundation
import Testing
import UMLDiagram
@testable import UMLApp

/// Coverage for configuration-derived auto-naming. A generated diagram's name follows its
/// configuration (via `autoName`) until the user renames it (`isNameUserDefined`).
@Suite("Generated Diagram Naming")
struct GeneratedDiagramNamingTests {

    @Test func sequenceNameDerivesFromEntryPoint() {
        let config = SequenceDiagramConfiguration(entryTypeName: "Login", entryMethodName: "run")
        let diagram = GeneratedDiagram(name: "", content: .sequenceDiagram(config), codebaseID: UUID())
        #expect(diagram.autoName(codebaseName: "MyApp") == "MyApp — Sequence: Login.run")
    }

    @Test func stateNameDerivesFromVariable() {
        let withType = StateDiagramConfiguration(typeName: "Loader", variableName: "state", maxStates: 10)
        let scoped = GeneratedDiagram(name: "", content: .stateDiagram(withType), codebaseID: UUID())
        #expect(scoped.autoName(codebaseName: "MyApp") == "MyApp — State: Loader.state")

        let global = StateDiagramConfiguration(typeName: nil, variableName: "phase", maxStates: 10)
        let unscoped = GeneratedDiagram(name: "", content: .stateDiagram(global), codebaseID: UUID())
        #expect(unscoped.autoName(codebaseName: "MyApp") == "MyApp — State: phase")
    }

    @Test func typeOnlyKindsUseDisplayName() {
        let cases: [(GeneratedDiagram.Content, DiagramType)] = [
            (.classDiagram(.init()), .classDiagram),
            (.stateDiagram(nil), .stateDiagram),
            (.useCaseDiagram, .useCaseDiagram),
            (.deploymentDiagram, .deploymentDiagram)
        ]
        for (content, type) in cases {
            let diagram = GeneratedDiagram(name: "", content: content, codebaseID: UUID())
            #expect(diagram.autoName(codebaseName: "MyApp") == "MyApp — \(type.displayName)")
        }
    }

    @Test func emptyCodebaseNameOmitsPrefix() {
        let config = SequenceDiagramConfiguration(entryTypeName: "A", entryMethodName: "b")
        let diagram = GeneratedDiagram(name: "", content: .sequenceDiagram(config), codebaseID: UUID())
        #expect(diagram.autoName(codebaseName: "") == "Sequence: A.b")
    }

    @Test func newDiagramIsNotUserNamed() {
        let diagram = GeneratedDiagram(name: "X", content: .deploymentDiagram, codebaseID: UUID())
        #expect(diagram.isNameUserDefined == false)
    }
}
