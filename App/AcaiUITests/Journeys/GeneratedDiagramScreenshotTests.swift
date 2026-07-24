import XCTest

/// Golden screenshots for the four generated diagram types not already covered by
/// `ScreenshotJourneyTests`/`CompareGitRevisionTests` (Class Diagram): Sequence, State, Package, and
/// Call Graph. Each test reindexes the `seeded` fixture's `SampleSwiftPackage` codebase fresh — its
/// `Base`/`Derived`/`Helper`/`Worker` types form a `Derived.doWork() -> Helper.performTask() ->
/// Worker.execute()` composition chain (for Sequence/Call Graph) and a `Base.id` chain-with-branch
/// (`run()`'s `"requested" -> "running" -> "finished"` chain, `fail()`'s `"failed"` branch, for
/// State) — patterned directly on `Examples/CallGraph/Swift`, `Examples/SequenceDiagram/Swift`, and
/// `Examples/StateDiagram/Swift/Download.swift` so this fixture doesn't invent a fifth shape of demo
/// content. See `TESTING_ARCHITECTURE.md` Layer 2.
final class GeneratedDiagramScreenshotTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private var comparator: ScreenshotComparator {
        ScreenshotComparator(goldenDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__"))
    }

    /// Launches the seeded fixture and reindexes it, returning `CodebaseDetailScreen` once every
    /// `codebaseDetail.diagramButton.*` is available — shared preamble for all four tests below.
    private func launchReindexedCodebase(_ app: XCUIApplication) -> CodebaseDetailScreen {
        app.launchWithFixture("seeded")

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
        let app = XCUIApplication()
        let codebaseDetail = launchReindexedCodebase(app)

        let sequence = SequenceDiagramScreen(app: app)
        let sequenceButton = codebaseDetail.diagramButton(type: "sequence")
        sequenceButton.tapUntil(sequence.typePicker)

        sequence.typePicker.choose("Derived", in: app)
        sequence.methodPicker.choose("doWork", in: app)
        sequence.nextButton.tap()

        XCTAssertTrue(sequence.participant(named: "Derived").waitForExistence(timeout: 10))
        XCTAssertTrue(sequence.participant(named: "Helper").exists)
        XCTAssertTrue(sequence.participant(named: "Worker").exists)

        // A freshly-created diagram opens at its default scale/offset, not auto-fit — with 3
        // participants side by side, only the first is on-screen until this fits the whole layout.
        sequence.fitToViewButton.tap()
        comparator.validate(
            viewType: "SequenceDiagram", state: "populated",
            screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )
    }

    func testStateDiagramScreenshot() throws {
        let app = XCUIApplication()
        let codebaseDetail = launchReindexedCodebase(app)

        let state = StateDiagramScreen(app: app)
        let stateButton = codebaseDetail.diagramButton(type: "state")
        stateButton.tapUntil(state.scopePicker)

        state.scopePicker.choose("Base", in: app)
        state.variablePicker.choose("id", in: app)
        state.createButton.tap()

        // A freshly-created diagram opens at its default scale/offset, not auto-fit (unlike
        // re-editing an existing diagram's configuration, which does call `centerDiagram()`) — with
        // 5 nodes across a branching layout, the initial/failed states can start outside the visible
        // canvas, unlike Class/Sequence's smaller default layouts.
        XCTAssertTrue(state.fitToViewButton.waitForExistence(timeout: 10))
        state.fitToViewButton.tap()

        // `Base.id`'s values are Swift string-literal assignments (`id = "idle"`, etc.), and
        // `StateNodeView`'s label is the assignment's raw source text — quotes included, not the
        // unquoted string value — so the state's name (and this identifier) is literally `"idle"`.
        XCTAssertTrue(state.stateNode(named: "\"idle\"").waitForExistence(timeout: 10))
        XCTAssertTrue(state.stateNode(named: "\"requested\"").exists)
        XCTAssertTrue(state.stateNode(named: "\"failed\"").exists)
        comparator.validate(
            viewType: "StateDiagram", state: "populated",
            screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )
    }

    func testPackageDiagramScreenshot() throws {
        let app = XCUIApplication()
        let codebaseDetail = launchReindexedCodebase(app)

        let package = PackageDiagramScreen(app: app)
        let packageButton = codebaseDetail.diagramButton(type: "package")
        packageButton.tapUntil(package.containerNode(named: "SampleSwiftPackage"))

        XCTAssertTrue(package.containerNode(named: "SampleSwiftPackage").waitForExistence(timeout: 10))

        // A freshly-created diagram opens at its default scale/offset, not auto-fit — the single
        // package box starts mostly off-screen until this fits it into view.
        package.fitToViewButton.tap()
        comparator.validate(
            viewType: "PackageDiagram", state: "populated",
            screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )
    }

    func testCallGraphScreenshot() throws {
        let app = XCUIApplication()
        let codebaseDetail = launchReindexedCodebase(app)

        let callGraph = CallGraphScreen(app: app)
        let callGraphButton = codebaseDetail.diagramButton(type: "callGraph")
        callGraphButton.tapUntil(callGraph.createButton)

        // "Whole Codebase" is the config sheet's default selection — no scope picker interaction
        // needed for a meaningful graph.
        callGraph.createButton.tap()

        XCTAssertTrue(callGraph.node(id: "Derived.doWork").waitForExistence(timeout: 10))
        XCTAssertTrue(callGraph.node(id: "Helper.performTask").exists)
        XCTAssertTrue(callGraph.node(id: "Worker.execute").exists)

        // A freshly-created diagram opens at its default scale/offset, not auto-fit — with 3 nodes
        // side by side, only one is on-screen until this fits the whole layout.
        callGraph.fitToViewButton.tap()
        comparator.validate(
            viewType: "CallGraph", state: "populated",
            screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )
    }
}
