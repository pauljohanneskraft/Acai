import CoreGraphics
import Testing
import UMLCore
import UMLDiagram
import UMLRender
@testable import UMLApp

@Suite("Sequence Diagram View Model")
@MainActor
struct SequenceDiagramViewModelTests {

    /// `Service.run` calls `Repository.save`, so a trace from `Service.run` yields two participants.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Service.swift"]),
            types: [
                TypeDeclaration(
                    id: "Service", name: "Service", qualifiedName: "Service", kind: .class,
                    members: [
                        Member(name: "run", kind: .method, callSites: [
                            CallSite(receiverType: "Repository", methodName: "save")
                        ])
                    ]
                ),
                TypeDeclaration(
                    id: "Repository", name: "Repository", qualifiedName: "Repository", kind: .class,
                    members: [Member(name: "save", kind: .method)]
                )
            ]
        )
    }

    private func config(type: String = "Service", method: String = "run") -> SequenceDiagramConfiguration {
        SequenceDiagramConfiguration(entryTypeName: type, entryMethodName: method)
    }

    @Test func generatesParticipantsForTraceableEntryPoint() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        #expect(vm.diagram.participants.map(\.name) == ["Service", "Repository"])
        #expect(!vm.isEmpty)
    }

    @Test func untraceableEntryPointIsEmpty() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config(type: "Nope", method: "x"))
        #expect(vm.isEmpty)
    }

    @Test func restoredPositionsSeedState() {
        let vm = SequenceDiagramViewModel(
            artifact: artifact(), configuration: config(),
            restoredPositions: ["Service": CGPoint(x: 99, y: 0)]
        )
        #expect(vm.positionOverrides["Service"]?.x == 99)
    }

    @Test func moveNodeRecordsDragAndLayoutPinsVertical() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        let yBefore = vm.nodePosition("Service")?.y
        vm.moveNode("Service", to: CGPoint(x: 42, y: 999))
        #expect(vm.positionOverrides["Service"]?.x == 42)
        // Lifelines move horizontally only: the override's y is pinned to 0 so nothing meaningless
        // is persisted (a drag's vertical component must not leak into the saved positions).
        #expect(vm.positionOverrides["Service"]?.y == 0)
        // Only the horizontal component reaches the layout, so the lifeline stays on the header row.
        #expect(vm.nodePosition("Service")?.y == yBefore)
    }

    @Test func resizeNodeIsNoOp() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        vm.resizeNode("Service", width: 500, height: 500)
        #expect(vm.positionOverrides.isEmpty)
    }

    @Test func selectionTogglesExtendsAndClears() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        vm.selectNode("Service", extending: false)
        #expect(vm.selectedNodeIDs == ["Service"])
        vm.selectNode("Repository", extending: true)
        #expect(vm.selectedNodeIDs == ["Service", "Repository"])
        vm.selectNode("Repository", extending: true)
        #expect(vm.selectedNodeIDs == ["Service"])
        vm.clearSelection()
        #expect(vm.selectedNodeIDs.isEmpty)
    }

    @Test func selectAllSelectsEveryParticipant() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        vm.selectAll()
        #expect(vm.selectedNodeIDs == ["Service", "Repository"])
    }

    @Test func selectNodesInRectSelectsContainedParticipants() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        // A rect spanning the whole layout selects every participant.
        vm.selectNodes(in: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000))
        #expect(vm.selectedNodeIDs == ["Service", "Repository"])
    }

    @Test func applyConfigurationRegeneratesAndClearsTransientState() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        vm.moveNode("Service", to: CGPoint(x: 10, y: 0))
        vm.selectNode("Service", extending: false)

        vm.applyConfiguration(config(type: "Nope", method: "x"))
        #expect(vm.isEmpty)
        #expect(vm.positionOverrides.isEmpty)
        #expect(vm.selectedNodeIDs.isEmpty)
    }

    @Test func historySnapshotMirrorsOverrides() {
        let vm = SequenceDiagramViewModel(artifact: artifact(), configuration: config())
        vm.positionOverrides = ["Service": CGPoint(x: 7, y: 0)]
        #expect(vm.historySnapshot == ["Service": CGPoint(x: 7, y: 0)])
        vm.historySnapshot = ["Repository": CGPoint(x: 3, y: 0)]
        #expect(vm.positionOverrides == ["Repository": CGPoint(x: 3, y: 0)])
    }
}
