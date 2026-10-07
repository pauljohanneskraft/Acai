import XCTest

/// Golden screenshots for the four generated diagram types not already covered by
/// `ScreenshotJourneyTests`/`CompareGitRevisionTests` (Class Diagram): Sequence, State, Package, and
/// Call Graph — each also filtered to nothing and back through the empty-scope overlay. The seeded fixture's `Base`/`Derived`/`Helper`/`Worker` types are patterned directly
/// on `Examples/CallGraph/Swift`, `Examples/SequenceDiagram/Swift`, and
/// `Examples/StateDiagram/Swift/Download.swift` so this fixture doesn't invent a fifth shape of demo
/// content.
@MainActor
final class GeneratedDiagramScreenshotTests: UIJourneyTestCase {
    func testSequenceDiagramScreenshot() throws {
        let codebaseDetail = openPreindexedSeededCodebase()
        let sequence = codebaseDetail.openDiagramConfiguration(
            type: "sequence", as: SequenceDiagramScreen.self, until: { $0.typePicker }
        )

        sequence.typePicker.choose("Derived", in: app)
        sequence.methodPicker.choose("doWork", in: app)
        sequence.nextButton.tapWhenReady("the sequence configuration's Next button")

        sequence.participant(named: "Derived").waitOrFail("the Derived participant", timeout: .uiWork)
        XCTAssertTrue(sequence.participant(named: "Helper").exists, "Helper should be a participant")
        XCTAssertTrue(sequence.participant(named: "Worker").exists, "Worker should be a participant")

        sequence.tapFitToView()
        validateScreenshot("SequenceDiagram", state: "populated")

        sequence.filterEverythingAway(hiding: sequence.participant(named: "Helper"))
        XCTAssertFalse(sequence.participant(named: "Derived").exists, "the entry point's lifeline should be hidden too")
        sequence.clearEmptyFilter(restoring: sequence.participant(named: "Helper"))
    }

    func testStateDiagramScreenshot() throws {
        let codebaseDetail = openPreindexedSeededCodebase()
        let state = codebaseDetail.openDiagramConfiguration(
            type: "state", as: StateDiagramScreen.self, until: { $0.scopePicker }
        )

        state.scopePicker.choose("Base", in: app)
        state.variablePicker.choose("id", in: app)
        state.createButton.tapWhenReady("the state configuration's Create button")

        // `StateNodeView`'s label is the assignment's raw source text, quotes included, so the
        // state's name (and this identifier) is literally `"idle"`.
        state.stateNode(named: "\"idle\"").waitOrFail("the idle state node", timeout: .uiWork)
        XCTAssertTrue(state.stateNode(named: "\"requested\"").exists, "the requested state should be drawn")
        XCTAssertTrue(state.stateNode(named: "\"failed\"").exists, "the failed state should be drawn")

        state.tapFitToView()
        validateScreenshot("StateDiagram", state: "populated")

        state.filterEverythingAway(hiding: state.stateNode(named: "\"idle\""))
        state.clearEmptyFilter(restoring: state.stateNode(named: "\"idle\""))
    }

    func testPackageDiagramScreenshot() throws {
        let codebaseDetail = openPreindexedSeededCodebase()
        let package = codebaseDetail.createDiagram(type: "package", as: PackageDiagramScreen.self)

        package.containerNode(named: "SampleSwiftPackage").waitOrFail("the SampleSwiftPackage module", timeout: .uiWork)

        package.tapFitToView()
        validateScreenshot("PackageDiagram", state: "populated")

        // A type glob would hide no module: package nodes match only on the module facet.
        let module = package.containerNode(named: "SampleSwiftPackage")
        package.filterEverythingAway(using: package.filterModuleGlobField, hiding: module)
        package.clearEmptyFilter(restoring: module)
    }

    func testCallGraphScreenshot() throws {
        let codebaseDetail = openPreindexedSeededCodebase()
        let callGraph = codebaseDetail.openDiagramConfiguration(
            type: "callGraph", as: CallGraphScreen.self, until: { $0.createButton }
        )
        callGraph.createButton.tapWhenReady("the call graph configuration's Create button")

        callGraph.node(id: "Derived.doWork").waitOrFail("the Derived.doWork node", timeout: .uiWork)
        XCTAssertTrue(callGraph.node(id: "Helper.performTask").exists, "Helper.performTask should be drawn")
        XCTAssertTrue(callGraph.node(id: "Worker.execute").exists, "Worker.execute should be drawn")

        callGraph.tapFitToView()
        validateScreenshot("CallGraph", state: "populated")

        callGraph.filterEverythingAway(hiding: callGraph.node(id: "Derived.doWork"))
        callGraph.clearEmptyFilter(restoring: callGraph.node(id: "Derived.doWork"))
    }
}
