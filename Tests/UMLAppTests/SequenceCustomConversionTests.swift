import CoreGraphics
import Foundation
import Testing
import UMLCore
import UMLDiagram
@testable import UMLApp

/// "Save as Custom" for sequence diagrams: participants become lifeline nodes at their exact
/// generated x positions, and *every* message — calls and returns — becomes a time-ordered
/// message edge, so the custom editor (which renders through the same sequence layout) shows
/// a pixel-identical diagram.
@Suite("Sequence → Custom Conversion")
@MainActor
struct SequenceCustomConversionTests {

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Caller", name: "Caller", qualifiedName: "Caller", kind: .class,
                    members: [Member(
                        name: "run", kind: .method,
                        callSites: [CallSite(receiverType: "Callee", methodName: "work")]
                    )]
                ),
                TypeDeclaration(
                    id: "Callee", name: "Callee", qualifiedName: "Callee", kind: .class,
                    members: [Member(name: "work", kind: .method)]
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
        let custom = sequenceDiagram().convertToCustom(
            artifact: artifact(),
            positions: ["Caller": CGPoint(x: 80, y: 0), "Callee": CGPoint(x: 320, y: 0)],
            scale: 1, offset: .zero
        )

        #expect(custom.diagramType == .sequenceDiagram)
        #expect(custom.nodes.count == 2)
        for node in custom.nodes {
            guard case .lifeline = node.content else {
                Issue.record("expected lifeline content, got \(node.content)")
                return
            }
        }
        let byName = Dictionary(uniqueKeysWithValues: custom.nodes.map { ($0.name, $0) })
        #expect(byName["Caller"]?.positionX == 80)
        #expect(byName["Callee"]?.positionX == 320)
    }

    @Test("Calls and returns both convert into ordered message edges")
    func messagesIncludeReturns() {
        let custom = sequenceDiagram().convertToCustom(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )

        // One synchronous call + its return.
        #expect(custom.edges.count == 2)
        #expect(custom.edges.allSatisfy { $0.messageOrder != nil })
        let kinds = custom.edges.compactMap(\.messageKind)
        #expect(kinds.contains(.synchronous))
        #expect(kinds.contains(.return))
        // Labels carry the method name without any numbering prefix.
        #expect(custom.edges.contains { $0.label == "work" })
        // Strictly increasing time order.
        let orders = custom.edges.compactMap(\.messageOrder)
        #expect(orders == orders.sorted())
        #expect(Set(orders).count == orders.count)
    }

    @Test("The converted diagram round-trips through the custom view model's sequence layout")
    func customViewModelReproducesSequence() {
        let custom = sequenceDiagram().convertToCustom(
            artifact: artifact(),
            positions: ["Caller": CGPoint(x: 80, y: 0), "Callee": CGPoint(x: 320, y: 0)],
            scale: 1, offset: .zero
        )

        let vm = CustomDiagramViewModel()
        vm.nodes = custom.nodes
        vm.edges = custom.edges

        guard let layout = vm.sequenceLayout else {
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
