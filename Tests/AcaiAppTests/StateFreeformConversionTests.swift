import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// "Save as Freeform" for state diagrams: states become state nodes at their generated
/// positions and every transition becomes a labeled transition edge, so the freeform editor
/// (which renders through the same `StateNodeView`) shows an identical diagram.
@Suite("State → Freeform Conversion")
@MainActor
struct StateFreeformConversionTests {

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [TypeDeclaration(
                id: "Loader", name: "Loader", qualifiedName: "Loader", kind: .class,
                accessLevel: .public,
                members: [
                    Member(
                        name: "state", kind: .property,
                        accessLevel: .internal,
                        type: TypeReference(name: "State"),
                        initialValue: .init(kind: .enumCase, text: "idle")
                    ),
                    Member(
                        name: "load", kind: .method,
                        accessLevel: .internal,
                        assignments: [
                            .init(targetName: "state", op: .assign,
                                  value: .init(kind: .enumCase, text: "loading")),
                            .init(targetName: "state", op: .assign,
                                  value: .init(kind: .enumCase, text: "loaded"))
                        ]
                    )
                ]
            )]
        )
    }

    private func stateDiagram() -> GeneratedDiagram {
        GeneratedDiagram(
            name: "States",
            content: .stateDiagram(.init(typeName: "Loader", variableName: "state")),
            codebaseID: UUID()
        )
    }

    @Test("States become state nodes with their kinds and positions")
    func statesBecomeStateNodes() {
        let freeform = stateDiagram().convertToFreeform(
            artifact: artifact(),
            positions: ["state_idle": CGPoint(x: 80, y: 200)],
            scale: 1, offset: .zero
        )

        // __initial + idle + loading + loaded
        #expect(freeform.nodes.count == 4)
        let kinds = freeform.nodes.compactMap { node -> StateDiagram.State.Kind? in
            if case .state(let kind) = node.content { kind } else { nil }
        }
        #expect(kinds.count == 4)
        #expect(kinds.filter { $0 == .initial }.count == 1)
        let idle = freeform.nodes.first { $0.name == "idle" }
        #expect(idle?.positionX == 80)
        #expect(idle?.positionY == 200)
    }

    @Test("Transitions become labeled transition edges")
    func transitionsBecomeEdges() {
        let freeform = stateDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )

        #expect(!freeform.edges.isEmpty)
        #expect(freeform.edges.allSatisfy { $0.transition != nil })
        // The intra-method chain keeps its event label.
        #expect(freeform.edges.contains { $0.transition?.event == "load()" })
        // Edge endpoints all resolve to nodes.
        let nodeIDs = Set(freeform.nodes.map(\.id))
        for edge in freeform.edges {
            #expect(nodeIDs.contains(edge.sourceNodeID))
            #expect(nodeIDs.contains(edge.targetNodeID))
        }
    }

    @Test("A failing analysis converts to an empty editable diagram")
    func failingAnalysisConvertsEmpty() {
        let diagram = GeneratedDiagram(
            name: "Broken",
            content: .stateDiagram(.init(typeName: "Missing", variableName: "nope")),
            codebaseID: UUID()
        )
        let freeform = diagram.convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )
        #expect(freeform.nodes.isEmpty)
        #expect(freeform.edges.isEmpty)
    }

    @Test("Transition edge label formats as UML event [guard] / action")
    func transitionLabelFormatting() {
        var transition = FreeformDiagram.Edge.Transition(event: "load()")
        #expect(transition.label == "load()")
        transition.guardCondition = "ok"
        transition.action = "notify"
        #expect(transition.label == "load() [ok] / notify")
        #expect(FreeformDiagram.Edge.Transition().label == nil)
    }
}
