import XCTest

/// Extends #185's "every generated diagram type supports comparison" to Sequence, State, Package
/// and Call Graph — Class Diagram's own compare flow is already covered end-to-end by
/// `CompareGitRevisionTests`. Sequence and State had no `CompareOverlayButton` at all before this
/// change; Package and Call Graph could already load a comparison snapshot but showed no per-element
/// detail. This proves, for each: the button now exists, and choosing a ref reaches `loaded` with no
/// error — the same `seeded-with-added`/`comparison-HEAD` fixture pair `CompareGitRevisionTests`
/// uses, whose only difference is a member-less `Added` type. That's enough to prove every diagram
/// type's comparison plumbing (ref picking, snapshot loading, the union diagram) works without
/// erroring; it doesn't produce a call-graph node, package module, or sequence/state member for
/// `Added` to badge, since it has no methods and isn't referenced from any entry point or state
/// variable — the added/removed/changed badge and the inspector's "Comparison" row are covered
/// directly by `AcaiDiffTests` (`SequenceDiagramDiffTests`, `StateDiagramDiffTests`,
/// `ArtifactDifferTests`) instead. A richer fixture that reaches the traced methods/modules would let
/// a future journey assert the visible badge too.
@MainActor
final class CompareOtherDiagramTypesTests: UIJourneyTestCase {

    override var stopsAtFirstFailure: Bool { false }
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private func launchReindexedCodebase(_ app: XCUIApplication) -> CodebaseDetailScreen {
        app.rotateToLandscapeOnIPad()
        app.launchWithFixture("seeded") { app, destination in
            let artifactsDir = destination.appendingPathComponent("artifacts")
            app.launchEnvironment["ACAI_UITEST_CODEBASE_ARTIFACTS"] = app.environmentRecords([
                [Self.codebaseID, artifactsDir.appendingPathComponent("seeded-with-added.json").path]
            ])
            app.launchEnvironment["ACAI_UITEST_COMPARISON_ARTIFACTS"] = app.environmentRecords([
                [Self.codebaseID, "HEAD", artifactsDir.appendingPathComponent("comparison-HEAD.json").path]
            ])
        }

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        projectRow.tapUntil(codebaseRow)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        codebaseRow.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10))
        codebaseDetail.reindexButton.tap()

        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 30), "the codebase never finished indexing")
        return codebaseDetail
    }

    /// Asserts the compare button now exists and a comparison against HEAD loads without error —
    /// shared by every case below, matching `CompareGitRevisionTests`'s own assertions minus the
    /// visual delta (which this fixture pair can't produce for these diagram types).
    private func assertComparisonLoads(
        _ diagram: DiagramScreenBase, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(diagram.compareButton.waitForExistence(timeout: 10), file: file, line: line)
        diagram.openCompare(file: file, line: line)
        diagram.chooseCompareRef("HEAD", file: file, line: line)
        let loaded = diagram.compareLoadedIndicator.waitForExistence(timeout: 10)
        let errorExists = diagram.compareErrorIndicator.exists
        let errorMessage = errorExists ? diagram.compareErrorIndicator.label : "(no error shown)"
        XCTAssertTrue(loaded, "comparison snapshot never finished loading: \(errorMessage)", file: file, line: line)
        XCTAssertFalse(errorExists, errorMessage, file: file, line: line)
    }

    func testSequenceDiagramComparisonLoads() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let sequence = SequenceDiagramScreen(app: app)
        let sequenceButton = codebaseDetail.diagramButton(type: "sequence")
        sequenceButton.tapUntil(sequence.typePicker)

        sequence.typePicker.choose("Derived", in: app)
        sequence.methodPicker.choose("doWork", in: app)
        sequence.nextButton.tap()

        XCTAssertTrue(sequence.participant(named: "Derived").waitForExistence(timeout: 30))
        assertComparisonLoads(sequence)
    }

    func testStateDiagramComparisonLoads() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let state = StateDiagramScreen(app: app)
        let stateButton = codebaseDetail.diagramButton(type: "state")
        stateButton.tapUntil(state.scopePicker)

        state.scopePicker.choose("Base", in: app)
        state.variablePicker.choose("id", in: app)
        state.createButton.tap()

        XCTAssertTrue(state.stateNode(named: "\"idle\"").waitForExistence(timeout: 30))
        assertComparisonLoads(state)
    }

    func testPackageDiagramComparisonLoads() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let package = PackageDiagramScreen(app: app)
        let packageButton = codebaseDetail.diagramButton(type: "package")
        packageButton.tapUntilItDisappears()

        XCTAssertTrue(package.containerNode(named: "SampleSwiftPackage").waitForExistence(timeout: 30))
        assertComparisonLoads(package)
    }

    func testCallGraphComparisonLoads() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let callGraph = CallGraphScreen(app: app)
        let callGraphButton = codebaseDetail.diagramButton(type: "callGraph")
        callGraphButton.tapUntil(callGraph.createButton)
        callGraph.createButton.tap()

        XCTAssertTrue(callGraph.node(id: "Derived.doWork").waitForExistence(timeout: 30))
        assertComparisonLoads(callGraph)
    }
}
