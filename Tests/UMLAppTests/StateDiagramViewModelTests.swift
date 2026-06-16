import CoreGraphics
import Testing
import UMLCore
import UMLDiagram
import UMLRender
@testable import UMLApp

@Suite("State Diagram View Model")
@MainActor
struct StateDiagramViewModelTests {

    /// `Loader.state` moves through idle → loading → loaded / failed.
    private func artifact() -> CodeArtifact {
        let stateProperty = Member(
            name: "state", kind: .property,
            type: TypeReference(name: "State"),
            initialValue: .init(kind: .enumCase, text: "idle")
        )
        let load = Member(
            name: "load", kind: .method,
            assignments: [
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loading")),
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loaded"))
            ]
        )
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [TypeDeclaration(
                id: "Loader", name: "Loader", qualifiedName: "Loader", kind: .class,
                members: [stateProperty, load]
            )]
        )
    }

    private func config(variable: String = "state") -> StateDiagramConfiguration {
        StateDiagramConfiguration(typeName: "Loader", variableName: variable)
    }

    @Test func successfulAnalysisExposesDiagram() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        #expect(vm.diagram != nil)
        #expect(vm.analysisError == nil)
        #expect(vm.diagram?.states.contains { $0.name == "loading" } == true)
    }

    @Test func failedAnalysisExposesErrorNotDiagram() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config(variable: "missing"))
        #expect(vm.diagram == nil)
        #expect(vm.analysisError == .variableNotFound(typeName: "Loader", variableName: "missing"))
    }

    @Test func nilConfigurationProducesNoResult() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: nil)
        #expect(vm.diagram == nil)
        #expect(vm.analysisError == nil)
    }

    @Test func restoredPositionsSeedState() {
        let vm = StateDiagramViewModel(
            artifact: artifact(), configuration: config(),
            restoredPositions: ["state_idle": CGPoint(x: 5, y: 6)]
        )
        #expect(vm.positionOverrides["state_idle"] == CGPoint(x: 5, y: 6))
    }

    @Test func moveNodeUpdatesOverrideAndResizeIsNoOp() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.moveNode("state_idle", to: CGPoint(x: 11, y: 22))
        #expect(vm.positionOverrides["state_idle"] == CGPoint(x: 11, y: 22))
        vm.resizeNode("state_idle", width: 400, height: 400)
        #expect(vm.positionOverrides["state_idle"] == CGPoint(x: 11, y: 22))
    }

    @Test func selectionTogglesExtendsAndClears() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.selectNode("state_idle", extending: false)
        #expect(vm.selectedNodeIDs == ["state_idle"])
        vm.selectNode("state_loading", extending: true)
        #expect(vm.selectedNodeIDs == ["state_idle", "state_loading"])
        vm.selectNode("state_loading", extending: true)
        #expect(vm.selectedNodeIDs == ["state_idle"])
        vm.clearSelection()
        #expect(vm.selectedNodeIDs.isEmpty)
    }

    @Test func selectNodesInRectSelectsContainedStates() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.selectNodes(in: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000))
        #expect(!vm.selectedNodeIDs.isEmpty)
        #expect(vm.selectedNodeIDs == Set(vm.layout.nodes.map(\.id)))
    }

    @Test func applyConfigurationReRunsAndClearsTransientState() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.moveNode("state_idle", to: CGPoint(x: 1, y: 1))
        vm.selectNode("state_idle", extending: false)

        vm.applyConfiguration(config(variable: "missing"))
        #expect(vm.diagram == nil)
        #expect(vm.analysisError != nil)
        #expect(vm.positionOverrides.isEmpty)
        #expect(vm.selectedNodeIDs.isEmpty)
    }

    @Test func historySnapshotMirrorsPositions() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.positionOverrides = ["state_idle": CGPoint(x: 3, y: 4)]
        #expect(vm.historySnapshot == ["state_idle": CGPoint(x: 3, y: 4)])
        vm.historySnapshot = ["state_loading": CGPoint(x: 9, y: 9)]
        #expect(vm.positionOverrides == ["state_loading": CGPoint(x: 9, y: 9)])
    }
}
