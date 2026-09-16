import XCTest

/// German is the longest of the three shipped languages, so it is the one the layouts have to hold
/// in. This walks the densest screens with the app running in German and diffs each against its own
/// golden — the only way a label that fits in English but truncates or clips in German is caught.
/// The pixel diff is the whole check: XCUITest reports a `Text`'s full string whether or not it was
/// rendered in full, so truncation is invisible to an assertion over accessibility labels.
@MainActor
final class GermanLayoutJourneyTests: UIJourneyTestCase {

    func testGermanLayoutHolds() throws {
        let browser = launchSeeded(analysis: .canned, language: "de")

        let projectRow = browser.projectRow(id: seeded.projectID)
        projectRow.waitOrFail("the seeded project's sidebar row")
        assertGermanIsInEffect(browser.newProjectButton)
        validateScreenshot("ProjectBrowser", state: "german")

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: seeded.codebaseID)
        projectRow.tap("the seeded project's sidebar row", until: codebaseRow)
        validateScreenshot("ProjectDetail", state: "german")

        let codebase = CodebaseDetailScreen(app: app)
        codebaseRow.tap("the seeded codebase's row", until: codebase.reindexButton)
        validateScreenshot("CodebaseDetail", state: "german")
    }

    /// Proves the process really came up in German before any layout claim is made about it — a
    /// German journey that silently ran in English would pass while checking nothing.
    private func assertGermanIsInEffect(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        element.waitOrFail("an element to check the language on", file: file, line: line)
        XCTAssertFalse(
            element.label.contains("New Project"),
            "the app came up in English — the -AppleLanguages launch argument did not take effect",
            file: file, line: line
        )
    }
}
