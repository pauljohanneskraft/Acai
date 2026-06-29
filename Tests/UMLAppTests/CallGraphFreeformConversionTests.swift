import CoreGraphics
import Foundation
import Testing
import UMLCore
import UMLDiagram
@testable import UMLApp

/// "Save as Freeform" for call graphs: each method becomes a `.method` node and every call a
/// dependency edge, so the freeform editor (which renders through the same `MethodNodeView`)
/// shows an identical graph.
@Suite("Call Graph → Freeform Conversion")
@MainActor
struct CallGraphFreeformConversionTests {

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiverType: "B", methodName: "work")
                        ])
                    ]
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "work", kind: .method, accessLevel: .internal)]
                )
            ]
        )
    }

    private func callGraphDiagram() -> GeneratedDiagram {
        GeneratedDiagram(name: "Calls", content: .callGraph(.wholeCodebase), codebaseID: UUID())
    }

    @Test("Methods become method nodes labelled Type.method")
    func methodsBecomeMethodNodes() {
        let freeform = callGraphDiagram().convertToFreeform(
            artifact: artifact(),
            positions: ["A.run": CGPoint(x: 64, y: 128)],
            scale: 1, offset: .zero
        )
        #expect(freeform.nodes.count == 2)
        #expect(freeform.nodes.allSatisfy { if case .method = $0.content { true } else { false } })
        #expect(Set(freeform.nodes.map(\.name)) == ["A.run", "B.work"])
        let runNode = freeform.nodes.first { $0.name == "A.run" }
        #expect(runNode?.positionX == 64)
        #expect(runNode?.positionY == 128)
    }

    @Test("Calls become dependency edges")
    func callsBecomeEdges() {
        let freeform = callGraphDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )
        #expect(freeform.edges.count == 1)
        #expect(freeform.edges.allSatisfy { $0.kind == .dependency })
    }

    @Test("Method kind round-trips through the freeform node-kind catalog")
    func methodKindRoundTrips() {
        let content = FreeformDiagramNodeKind.callGraphMethod.defaultContent()
        #expect(content.kind == .callGraphMethod)
        if case .method = content {} else { Issue.record("expected .method content") }
    }
}
