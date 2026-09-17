import XCTest

/// Extends #185's "every generated diagram type supports comparison" to Sequence, State, Package
/// and Call Graph — Class Diagram's own compare flow is covered end-to-end by
/// `CompareGitRevisionTests`. This proves, for each: the button exists, and choosing a ref reaches
/// `loaded` with no error — the same `seeded-with-added`/`comparison-HEAD` fixture pair
/// `CompareGitRevisionTests` uses, whose only difference is a member-less `Added` type. That proves
/// every diagram type's comparison plumbing (ref picking, snapshot loading, the union diagram)
/// works without erroring; it doesn't produce a call-graph node, package module, or sequence/state
/// member for `Added` to badge, since it has no methods and isn't referenced from any entry point or
/// state variable — the added/removed/changed badge and the inspector's "Comparison" row are
/// covered directly by `AcaiDiffTests` (`SequenceDiagramDiffTests`, `StateDiagramDiffTests`,
/// `ArtifactDifferTests`) instead.
@MainActor
final class CompareOtherDiagramTypesTests: UIJourneyTestCase {
    func testSequenceDiagramComparisonLoads() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .cannedComparedWithHEAD)
        let sequence = codebaseDetail.openDiagramConfiguration(
            type: "sequence", as: SequenceDiagramScreen.self, until: { $0.typePicker }
        )

        sequence.typePicker.choose("Derived", in: app)
        sequence.methodPicker.choose("doWork", in: app)
        sequence.nextButton.tapWhenReady("the sequence configuration's Next button")

        sequence.participant(named: "Derived").waitOrFail("the Derived participant", timeout: .uiWork)
        sequence.openCompare()
        sequence.compare(against: "HEAD")
    }

    func testStateDiagramComparisonLoads() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .cannedComparedWithHEAD)
        let state = codebaseDetail.openDiagramConfiguration(
            type: "state", as: StateDiagramScreen.self, until: { $0.scopePicker }
        )

        state.scopePicker.choose("Base", in: app)
        state.variablePicker.choose("id", in: app)
        state.createButton.tapWhenReady("the state configuration's Create button")

        state.stateNode(named: "\"idle\"").waitOrFail("the idle state node", timeout: .uiWork)
        state.openCompare()
        state.compare(against: "HEAD")
    }

    func testPackageDiagramComparisonLoads() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .cannedComparedWithHEAD)
        let package = codebaseDetail.createDiagram(type: "package", as: PackageDiagramScreen.self)

        package.containerNode(named: "SampleSwiftPackage").waitOrFail("the SampleSwiftPackage module", timeout: .uiWork)
        package.openCompare()
        package.compare(against: "HEAD")
    }

    func testCallGraphComparisonLoads() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .cannedComparedWithHEAD)
        let callGraph = codebaseDetail.openDiagramConfiguration(
            type: "callGraph", as: CallGraphScreen.self, until: { $0.createButton }
        )
        callGraph.createButton.tapWhenReady("the call graph configuration's Create button")

        callGraph.node(id: "Derived.doWork").waitOrFail("the Derived.doWork node", timeout: .uiWork)
        callGraph.openCompare()
        callGraph.compare(against: "HEAD")
    }
}
