import CoreGraphics
import Testing
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender
@testable import AcaiApp

@Suite("State Diagram View Model")
@MainActor
struct StateDiagramViewModelTests {

    /// `Loader.state` moves through idle → loading → loaded / failed.
    private func artifact() -> CodeArtifact {
        let stateProperty = Member(
            name: "state", kind: .property,
            accessLevel: .internal,
            type: TypeReference(name: "State"),
            initialValue: .init(kind: .enumCase, text: "idle")
        )
        let load = Member(
            name: "load", kind: .method,
            accessLevel: .internal,
            assignments: [
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loading")),
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loaded"))
            ]
        )
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [TypeDeclaration(
                id: "Loader", name: "Loader", qualifiedName: "Loader", kind: .class,
                accessLevel: .public,
                members: [stateProperty, load]
            )]
        )
    }

    private func config(
        variable: String = "state", filter: AcaiQuality.Selector? = nil
    ) -> StateDiagramConfiguration {
        StateDiagramConfiguration(typeName: "Loader", variableName: variable, filter: filter)
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

    @Test func filterKeepsOnlyMatchingStatesAndDropsTheirTransitions() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.applyFilter(Selector(typeGlob: "loading"))
        #expect(vm.diagram?.states.map(\.id).sorted() == ["__initial", "state_loading"])
        #expect(vm.diagram?.transitions.map(\.to) == ["state_loading"])
        #expect(vm.configuration?.filter == Selector(typeGlob: "loading"))
    }

    @Test func filterAlwaysKeepsInitialPseudoState() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.applyFilter(Selector(typeGlob: "nonexistent"))
        #expect(vm.diagram?.states.map(\.id) == ["__initial"])
        #expect(vm.diagram?.transitions.isEmpty == true)
    }

    @Test func filterKeepsPositionOverridesForSurvivingNodes() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.positionOverrides = ["state_loading": CGPoint(x: 5, y: 6)]
        vm.applyFilter(Selector(typeGlob: "loading"))
        #expect(vm.positionOverrides["state_loading"] == CGPoint(x: 5, y: 6))
    }

    @Test func clearingFilterRestoresEveryState() {
        let filtered = config(filter: Selector(typeGlob: "loading"))
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: filtered)
        #expect(vm.diagram?.states.map(\.id).sorted() == ["__initial", "state_loading"])
        vm.applyFilter(nil)
        #expect(vm.diagram?.states.map(\.id).sorted() == ["__initial", "state_idle", "state_loaded", "state_loading"])
    }

    @Test func historySnapshotMirrorsPositions() {
        let vm = StateDiagramViewModel(artifact: artifact(), configuration: config())
        vm.positionOverrides = ["state_idle": CGPoint(x: 3, y: 4)]
        #expect(vm.historySnapshot == ["state_idle": CGPoint(x: 3, y: 4)])
        vm.historySnapshot = ["state_loading": CGPoint(x: 9, y: 9)]
        #expect(vm.positionOverrides == ["state_loading": CGPoint(x: 9, y: 9)])
    }

    // MARK: - Delta mode

    /// `Loader` gains a `fail` method assigning `failed`, so only the newer revision's state space
    /// holds that state and the transition into it.
    private func artifact(withFailState: Bool) -> CodeArtifact {
        let stateProperty = Member(
            name: "state", kind: .property, accessLevel: .internal,
            type: TypeReference(name: "State"),
            initialValue: .init(kind: .enumCase, text: "idle")
        )
        let load = Member(
            name: "load", kind: .method, accessLevel: .internal,
            assignments: [
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loading")),
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loaded"))
            ]
        )
        let fail = Member(
            name: "fail", kind: .method, accessLevel: .internal,
            assignments: [
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loading")),
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "failed"))
            ]
        )
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [TypeDeclaration(
                id: "Loader", name: "Loader", qualifiedName: "Loader", kind: .class, accessLevel: .public,
                members: withFailState ? [stateProperty, load, fail] : [stateProperty, load]
            )]
        )
    }

    @Test func comparisonArtifactMarksAddedElements() throws {
        let vm = StateDiagramViewModel(
            artifact: artifact(withFailState: true), configuration: config(),
            comparisonArtifact: artifact(withFailState: false))

        #expect(vm.isDeltaMode)
        // Rendered as the union of both revisions, so every state is present to be tinted.
        #expect(vm.diagram?.states.contains { $0.id == "state_failed" } == true)
        #expect(vm.stateDeltaStatus("state_failed") == .added)
        #expect(vm.stateDeltaStatus("state_loading") == nil)

        let transitions = try #require(vm.diagram?.transitions)
        let added = try #require(transitions.first { $0.to == "state_failed" })
        let unchanged = try #require(transitions.first { $0.to == "state_loaded" })
        #expect(vm.transitionDeltaStatus(added) == .added)
        #expect(vm.transitionDeltaStatus(unchanged) == nil)
    }

    @Test func noComparisonArtifactMeansNoDeltaStatus() throws {
        let vm = StateDiagramViewModel(artifact: artifact(withFailState: true), configuration: config())
        #expect(!vm.isDeltaMode)
        #expect(vm.stateDeltaStatus("state_failed") == nil)
        let transition = try #require(vm.diagram?.transitions.first)
        #expect(vm.transitionDeltaStatus(transition) == nil)
    }
}
