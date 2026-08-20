import XCTest

/// Centralizes the default `waitForExistence(timeout:)` budgets, so future tuning is one edit
/// instead of another round of scattered per-call-site bumps.
struct UITestWaits {
    static let standard = UITestWaits()

    var short: TimeInterval = 10
    var long: TimeInterval = 30
}

@MainActor
extension XCUIElement {
    /// Waits, and fails at the *caller's* line if it never appears. A discarded
    /// `waitForExistence` reports a miss later as a confusing "failed to tap" inside a screen
    /// object, several steps away from the state that was actually wrong.
    func waitOrFail(
        _ description: String, timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(description) never appeared", file: file, line: line)
    }
}
