import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// "Save as Freeform" for sequence diagrams: participants become lifeline nodes at their exact
/// generated x positions, and *every* message — calls and returns — becomes a time-ordered
/// message edge, so the freeform editor (which renders through the same sequence layout) shows
/// a pixel-identical diagram.
@Suite("Sequence → Freeform Conversion")
@MainActor
struct SequenceFreeformConversionTests {

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Caller", name: "Caller", qualifiedName: "Caller", kind: .class,
                    accessLevel: .public,
                    members: [Member(
                        name: "run", kind: .method,
                        accessLevel: .internal,
                        callSites: [CallSite(receiver: .type("Callee"), methodName: "work")]
                    )]
                ),
                TypeDeclaration(
                    id: "Callee", name: "Callee", qualifiedName: "Callee", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "work", kind: .method, accessLevel: .internal)]
                )
            ]
        )
    }

    private func sequenceDiagram() -> GeneratedDiagram {
        GeneratedDiagram(
            name: "Trace",
            content: .sequenceDiagram(.init(entryTypeName: "Caller", entryMethodName: "run")),
            codebaseID: UUID()
        )
    }

    @Test("Participants become lifeline nodes at the passed positions")
    func participantsBecomeLifelines() {
        let freeform = sequenceDiagram().convertToFreeform(
            artifact: artifact(),
            positions: ["Caller": CGPoint(x: 80, y: 0), "Callee": CGPoint(x: 320, y: 0)],
            scale: 1, offset: .zero
        )

        #expect(freeform.nodes.count == 2)
        for node in freeform.nodes {
            guard case .lifeline = node.content else {
                Issue.record("expected lifeline content, got \(node.content)")
                return
            }
        }
        let byName = Dictionary(uniqueKeysWithValues: freeform.nodes.map { ($0.name, $0) })
        #expect(byName["Caller"]?.positionX == 80)
        #expect(byName["Callee"]?.positionX == 320)
    }

    @Test("Calls and returns both convert into ordered message edges")
    func messagesIncludeReturns() {
        let freeform = sequenceDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )

        // One synchronous call + its return.
        #expect(freeform.edges.count == 2)
        #expect(freeform.edges.allSatisfy { $0.messageOrder != nil })
        let kinds = freeform.edges.compactMap(\.messageKind)
        #expect(kinds.contains(.synchronous))
        #expect(kinds.contains(.return))
        // Labels carry the method name without any numbering prefix.
        #expect(freeform.edges.contains { $0.label == "work" })
        // Strictly increasing time order.
        let orders = freeform.edges.compactMap(\.messageOrder)
        #expect(orders == orders.sorted())
        #expect(Set(orders).count == orders.count)
    }

    @Test("The converted diagram round-trips through the freeform view model's sequence layout")
    func freeformViewModelReproducesSequence() {
        let freeform = sequenceDiagram().convertToFreeform(
            artifact: artifact(),
            positions: ["Caller": CGPoint(x: 80, y: 0), "Callee": CGPoint(x: 320, y: 0)],
            scale: 1, offset: .zero
        )

        let vm = FreeformDiagramViewModel()
        vm.nodes = freeform.nodes
        vm.edges = freeform.edges

        guard let layout = vm.sequence.sequenceLayout else {
            Issue.record("expected a sequence layout for a diagram with lifelines")
            return
        }
        // Lifelines sit exactly at the converted node positions.
        #expect(Set(layout.participants.map(\.lifelineX)) == [80, 320])
        // Both messages survive, in order, with the callee activation present.
        #expect(layout.messages.count == 2)
        #expect(layout.messages[0].y < layout.messages[1].y)
        #expect(!layout.activations.isEmpty)
    }
}
