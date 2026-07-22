import XCTest

/// Proves the Compare/diff engine (`AcaiGit`, wired through `DeltaComparisonBar`) actually works
/// end to end, on both platforms, through the real app UI — no manual click-through needed. Before
/// this slice, this feature was `#if os(macOS)`-gated and shelled out to `git archive`/`tar`; this
/// journey is what replaces the manual "run the app, add a codebase, toggle Compare" verification
/// pass `TESTING_ARCHITECTURE.md`'s rationale section now calls out explicitly.
///
/// The seeded fixture's codebase isn't a git repo by default; `GitFixtureRepository` turns it into
/// one at launch, commits its current (pre-edit) content as `HEAD`, then this test edits the
/// working tree afterward (adding `Added.swift`) *without* committing — so comparing the
/// (reindexed) current side against `HEAD` produces a real, visible delta rather than a vacuous
/// "compared two identical states" no-op.
final class CompareGitRevisionTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private var comparator: ScreenshotComparator {
        ScreenshotComparator(goldenDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__"))
    }

    func testComparingAgainstHEADShowsAnAddedTypeAfterAnUncommittedEdit() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded") { _, destination in
            let codebaseDir = destination.appendingPathComponent("SampleSwiftPackage")
            try GitFixtureRepository(directory: codebaseDir).commitInitialRevision(paths: ["Package.swift", "Sources"])
            try "public class Added {}\n".write(
                to: codebaseDir.appendingPathComponent("Sources/SampleSwiftPackage/Added.swift"),
                atomically: true, encoding: .utf8)
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
        classDiagramButton.tap()

        let diagram = ClassDiagramScreen(app: app)
        XCTAssertTrue(diagram.typeNode(named: "Added").waitForExistence(timeout: 10),
                      "the uncommitted edit should still be visible on the current (working-tree) side")

        // Toggle Compare vs git (default ref: HEAD) and wait for the "old" snapshot to load.
        XCTAssertTrue(diagram.compareToggle.waitForExistence(timeout: 10))
        diagram.tapCompareToggle()
        let loaded = diagram.compareLoadedIndicator.waitForExistence(timeout: 15)
        let errorExists = diagram.compareErrorIndicator.exists
        let errorMessage = errorExists ? diagram.compareErrorIndicator.label : "(no error shown)"
        XCTAssertTrue(loaded, "comparison snapshot never finished loading: \(errorMessage)")
        XCTAssertFalse(errorExists, errorMessage)

        comparator.validate("compareAgainstHEAD", screenshot: app.screenshot(), testCase: self)
    }
}
