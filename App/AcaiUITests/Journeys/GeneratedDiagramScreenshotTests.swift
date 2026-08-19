import XCTest

/// Golden screenshots for the four generated diagram types not already covered by
/// `ScreenshotJourneyTests`/`CompareGitRevisionTests` (Class Diagram): Sequence, State, Package, and
/// Call Graph. The seeded fixture's `Base`/`Derived`/`Helper`/`Worker` types are patterned directly
/// on `Examples/CallGraph/Swift`, `Examples/SequenceDiagram/Swift`, and
/// `Examples/StateDiagram/Swift/Download.swift` so this fixture doesn't invent a fifth shape of demo
/// content.
@MainActor
final class GeneratedDiagramScreenshotTests: UIJourneyTestCase {

    /// Several states are captured per run; see `UIJourneyTestCase.stopsAtFirstFailure`.
    override var stopsAtFirstFailure: Bool { false }
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private var comparator: ScreenshotComparator {
        ScreenshotComparator(goldenDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__"))
    }

    private func launchReindexedCodebase(_ app: XCUIApplication) -> CodebaseDetailScreen {
        app.rotateToLandscapeOnIPad()
        app.launchWithFixture("seeded") { app, destination in
            app.launchEnvironment["ACAI_UITEST_CODEBASE_ARTIFACTS"] = app.environmentRecords([
                [Self.codebaseID, destination.appendingPathComponent("artifacts/seeded.json").path]
            ])
        }

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        codebaseRow.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10))
        codebaseDetail.reindexButton.tap()

        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 30), "the codebase never finished indexing")
        return codebaseDetail
    }

    func testSequenceDiagramScreenshot() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let sequence = SequenceDiagramScreen(app: app)
        let sequenceButton = codebaseDetail.diagramButton(type: "sequence")
        sequenceButton.tapUntil(sequence.typePicker)

        sequence.typePicker.choose("Derived", in: app)
        sequence.methodPicker.choose("doWork", in: app)
        sequence.nextButton.tap()

        XCTAssertTrue(sequence.participant(named: "Derived").waitForExistence(timeout: 30))
        XCTAssertTrue(sequence.participant(named: "Helper").exists)
        XCTAssertTrue(sequence.participant(named: "Worker").exists)

        sequence.fitToViewButton.tap()
        comparator.validate(
            viewType: "SequenceDiagram", state: "populated",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )
    }

    func testStateDiagramScreenshot() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let state = StateDiagramScreen(app: app)
        let stateButton = codebaseDetail.diagramButton(type: "state")
        stateButton.tapUntil(state.scopePicker)

        state.scopePicker.choose("Base", in: app)
        state.variablePicker.choose("id", in: app)
        state.createButton.tap()

        XCTAssertTrue(state.fitToViewButton.waitForExistence(timeout: 30))
        state.fitToViewButton.tap()

        // `StateNodeView`'s label is the assignment's raw source text, quotes included, so the
        // state's name (and this identifier) is literally `"idle"`.
        XCTAssertTrue(state.stateNode(named: "\"idle\"").waitForExistence(timeout: 10))
        XCTAssertTrue(state.stateNode(named: "\"requested\"").exists)
        XCTAssertTrue(state.stateNode(named: "\"failed\"").exists)
        comparator.validate(
            viewType: "StateDiagram", state: "populated",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )
    }

    func testPackageDiagramScreenshot() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let package = PackageDiagramScreen(app: app)
        let packageButton = codebaseDetail.diagramButton(type: "package")
        packageButton.tapUntil(package.containerNode(named: "SampleSwiftPackage"))

        XCTAssertTrue(package.containerNode(named: "SampleSwiftPackage").waitForExistence(timeout: 10))

        package.fitToViewButton.tap()
        comparator.validate(
            viewType: "PackageDiagram", state: "populated",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )
    }

    func testCallGraphScreenshot() throws {
        let codebaseDetail = launchReindexedCodebase(app)

        let callGraph = CallGraphScreen(app: app)
        let callGraphButton = codebaseDetail.diagramButton(type: "callGraph")
        callGraphButton.tapUntil(callGraph.createButton)

        callGraph.createButton.tap()

        // 30s, not this file's usual 10s: call-graph creation can occasionally take noticeably
        // longer than the other diagram types' render to complete.
        XCTAssertTrue(callGraph.node(id: "Derived.doWork").waitForExistence(timeout: 30))
        XCTAssertTrue(callGraph.node(id: "Helper.performTask").exists)
        XCTAssertTrue(callGraph.node(id: "Worker.execute").exists)

        callGraph.fitToViewButton.tap()
        comparator.validate(
            viewType: "CallGraph", state: "populated",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )
    }
}
