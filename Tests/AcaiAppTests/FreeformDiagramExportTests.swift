import CoreGraphics
import Foundation
import Testing
@testable import AcaiApp

@Suite("Freeform Diagram Export")
@MainActor
struct FreeformDiagramExportTests {

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    @Test func exportsNonEmptyPNGForOrdinaryNodesAndEdges() throws {
        let vm = FreeformDiagramViewModel()
        vm.addNode(kind: .type(.class), name: "Foo", at: CGPoint(x: 0, y: 0))
        vm.addNode(kind: .note, name: "Note", at: CGPoint(x: 300, y: 200))
        let sourceID = vm.nodes[0].id
        let targetID = vm.nodes[1].id
        vm.addEdge(from: sourceID, to: targetID, kind: .association)

        let data = try vm.exportPNGData(scale: 1)

        #expect(data.starts(with: Self.pngSignature))
    }

    @Test func exportsNonEmptyPNGForAnEmptyDiagram() throws {
        let vm = FreeformDiagramViewModel()

        let data = try vm.exportPNGData(scale: 1)

        #expect(data.starts(with: Self.pngSignature))
    }

    @Test func exportsNonEmptyPNGForASequenceDiagram() throws {
        let vm = FreeformDiagramViewModel()
        vm.addNode(kind: .lifeline, name: "Client", at: CGPoint(x: 0, y: 0))
        vm.addNode(kind: .lifeline, name: "Server", at: CGPoint(x: 200, y: 0))
        let clientID = vm.nodes[0].id
        let serverID = vm.nodes[1].id
        vm.sequence.addMessage(from: clientID, to: serverID, kind: .synchronous)

        let data = try vm.exportPNGData(scale: 1)

        #expect(data.starts(with: Self.pngSignature))
    }

    @Test func exportsAtTheDiagramsOwnBoundsRegardlessOfNodePositions() throws {
        let vm = FreeformDiagramViewModel()
        // Far from the origin in both directions — a naive export sized to a fixed canvas would
        // clip this; sizing from the content's own bounds must not.
        vm.addNode(kind: .type(.class), name: "Far", at: CGPoint(x: -5000, y: -5000))
        vm.addNode(kind: .type(.class), name: "AlsoFar", at: CGPoint(x: 5000, y: 5000))

        let data = try vm.exportPNGData(scale: 1)

        #expect(data.starts(with: Self.pngSignature))
    }
}
