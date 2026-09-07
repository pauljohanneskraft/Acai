import XCTest

/// German is the longest of the three shipped languages, so it is the one the layouts have to hold
/// in. This walks the densest screens with the app running in German and diffs each against its own
/// golden — the only way a label that fits in English but truncates or clips in German is caught.
/// The pixel diff is the whole check: XCUITest reports a `Text`'s full string whether or not it was
/// rendered in full, so truncation is invisible to an assertion over accessibility labels.
@MainActor
final class GermanLayoutJourneyTests: UIJourneyTestCase {

    override var stopsAtFirstFailure: Bool { false }
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private var comparator: ScreenshotComparator {
        ScreenshotComparator(goldenDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__"))
    }

    func testGermanLayoutHolds() throws {
        app.rotateToLandscapeOnIPad()
        app.launchWithFixture("seeded", language: "de") { app, destination in
            app.launchEnvironment["ACAI_UITEST_CODEBASE_ARTIFACTS"] = app.environmentRecords([
                [Self.codebaseID, destination.appendingPathComponent("artifacts/seeded.json").path]
            ])
        }

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        assertGermanIsInEffect(browser.newProjectButton)
        comparator.validate(
            viewType: "ProjectBrowser", state: "german",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        XCTAssertTrue(detail.codebaseRow(id: Self.codebaseID).waitForExistence(timeout: 10))
        comparator.validate(
            viewType: "ProjectDetail", state: "german",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )

        detail.codebaseRow(id: Self.codebaseID).tap()
        let codebase = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebase.reindexButton.waitForExistence(timeout: 20))
        comparator.validate(
            viewType: "CodebaseDetail", state: "german",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )
    }

    /// Proves the process really came up in German before any layout claim is made about it — a
    /// German journey that silently ran in English would pass while checking nothing.
    private func assertGermanIsInEffect(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "no element to check the language on", file: file, line: line)
        XCTAssertFalse(
            element.label.contains("New Project"),
            "the app came up in English — the -AppleLanguages launch argument did not take effect",
            file: file, line: line
        )
    }
}
