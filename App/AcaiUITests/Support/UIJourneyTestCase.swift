import XCTest

/// Shared lifecycle for every journey. Owns the app under test so teardown is guaranteed, stops a
/// test at its first failure, and leaves behind what's needed to diagnose one.
@MainActor
class UIJourneyTestCase: XCTestCase {
    let app = XCUIApplication()

    /// `false` for journeys that validate several screenshot states in one method: aborting at the
    /// first over-threshold state would leave the later states uncaptured, and those captures are
    /// exactly what `Scripts/snapshots_accept.sh` consumes to refresh goldens.
    var stopsAtFirstFailure: Bool { true }

    // The `async` overrides, unlike the synchronous ones, inherit this class's `@MainActor`.
    override func setUp() async throws {
        try await super.setUp()
        // Otherwise a failed wait doesn't end the test — every later `waitForExistence` runs out its
        // full timeout too, so one real failure costs a minute of dead wall-clock and reports four
        // cascading assertions instead of the one that matters.
        continueAfterFailure = !stopsAtFirstFailure
    }

    override func tearDown() async throws {
        if (testRun?.failureCount ?? 0) > 0 {
            attachDiagnostics()
        }
        app.terminate()
        try await super.tearDown()
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
