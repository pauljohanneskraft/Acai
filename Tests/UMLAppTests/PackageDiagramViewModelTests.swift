import CoreGraphics
import Testing
import UMLCore
import UMLDiagram
import UMLRender
@testable import UMLApp

@Suite("Package Diagram View Model")
@MainActor
struct PackageDiagramViewModelTests {

    /// `ModuleA` (two classes) depends on `ModuleB` (one protocol) → two module nodes, one edge.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleA/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "A2", name: "A2", qualifiedName: "A2", kind: .class,
                    accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleA/A2.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .protocol,
                    accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleB/B.swift", line: 1, column: 1)
                )
            ],
            relationships: [
                Relationship(kind: .conformance, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "A2", target: "B")
            ]
        )
    }

    @Test func derivesModuleNodesAndEdgeFromArtifact() {
        let vm = PackageDiagramViewModel(artifact: artifact())
        #expect(Set(vm.diagram.nodes.map(\.name)) == ["ModuleA", "ModuleB"])
        #expect(vm.diagram.edges.count == 1)
    }

    @Test func moduleLookupReturnsBackingNodeOrNil() throws {
        let vm = PackageDiagramViewModel(artifact: artifact())
        let id = try #require(vm.diagram.nodes.first?.id)
        #expect(vm.module(for: id)?.id == id)
        #expect(vm.module(for: "no-such-module") == nil)
    }

    @Test func restoredPositionsSeedState() throws {
        let id = try #require(PackageDiagramViewModel(artifact: artifact()).diagram.nodes.first?.id)
        let vm = PackageDiagramViewModel(artifact: artifact(), restoredPositions: [id: CGPoint(x: 8, y: 9)])
        #expect(vm.positionOverrides[id] == CGPoint(x: 8, y: 9))
    }

    @Test func moveNodeUpdatesOverrideAndResizeIsNoOp() throws {
        let vm = PackageDiagramViewModel(artifact: artifact())
        let id = try #require(vm.diagram.nodes.first?.id)
        vm.moveNode(id, to: CGPoint(x: 12, y: 34))
        #expect(vm.positionOverrides[id] == CGPoint(x: 12, y: 34))
        vm.resizeNode(id, width: 999, height: 999)
        #expect(vm.positionOverrides[id] == CGPoint(x: 12, y: 34))
    }

    @Test func selectionTogglesExtendsAndClears() throws {
        let vm = PackageDiagramViewModel(artifact: artifact())
        let ids = vm.diagram.nodes.map(\.id)
        let first = try #require(ids.first)
        let second = try #require(ids.dropFirst().first)
        vm.selectNode(first, extending: false)
        #expect(vm.selectedNodeIDs == [first])
        vm.selectNode(second, extending: true)
        #expect(vm.selectedNodeIDs == [first, second])
        vm.selectNode(second, extending: true)
        #expect(vm.selectedNodeIDs == [first])
        vm.clearSelection()
        #expect(vm.selectedNodeIDs.isEmpty)
    }

    @Test func selectAllAndMarqueeSelectEveryModule() {
        let vm = PackageDiagramViewModel(artifact: artifact())
        vm.selectAll()
        #expect(vm.selectedNodeIDs == Set(vm.diagram.nodes.map(\.id)))

        vm.clearSelection()
        vm.selectNodes(in: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000))
        #expect(vm.selectedNodeIDs == Set(vm.layout.nodes.map(\.id)))
    }

    @Test func historySnapshotMirrorsPositions() {
        let vm = PackageDiagramViewModel(artifact: artifact())
        vm.positionOverrides = ["ModuleA": CGPoint(x: 1, y: 2)]
        #expect(vm.historySnapshot == ["ModuleA": CGPoint(x: 1, y: 2)])
        vm.historySnapshot = ["ModuleB": CGPoint(x: 3, y: 4)]
        #expect(vm.positionOverrides == ["ModuleB": CGPoint(x: 3, y: 4)])
    }

    @Test func exportsNonEmptyPNGData() throws {
        let vm = PackageDiagramViewModel(artifact: artifact())
        let data = try vm.exportPNGData(scale: 1)
        // A valid PNG starts with the 8-byte signature.
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
}
