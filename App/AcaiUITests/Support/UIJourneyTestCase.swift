import XCTest

/// Shared lifecycle for every journey. Owns the app under test so teardown is guaranteed, stops a
/// test at its first failure, and leaves behind what's needed to diagnose one.
@MainActor
class UIJourneyTestCase: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        // Without this, a failed wait doesn't end the test — every later `waitForExistence` runs out
        // its full timeout too, so one real failure costs a minute of dead wall-clock and reports
        // four cascading assertions instead of the one that matters.
        continueAfterFailure = false
    }

    override func tearDown() {
        if (testRun?.failureCount ?? 0) > 0 {
            attachDiagnostics()
        }
        app.terminate()
        super.tearDown()
    }

    /// A failing UI test is otherwise undiagnosable after the fact: only the screenshot journeys
    /// attach anything today, so a run that fails anywhere else leaves nothing but the assertion
    /// message behind.
    private func attachDiagnostics() {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(name) — screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name) — element tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
