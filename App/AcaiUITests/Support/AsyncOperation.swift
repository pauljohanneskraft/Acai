import XCTest

/// The UI-test side of the app's `AsyncOperationStatusView`: every user-initiated async operation
/// exposes `<prefix>.loading`, `<prefix>.loaded` and `<prefix>.error`. Waiting on these is the only
/// reliable way to know background work finished — a downstream element usually exists before it did.
@MainActor
struct AsyncOperation {
    let app: XCUIApplication
    let identifierPrefix: String

    var loading: XCUIElement { app.descendants(matching: .any)["\(identifierPrefix).loading"] }
    var loaded: XCUIElement { app.descendants(matching: .any)["\(identifierPrefix).loaded"] }
    var error: XCUIElement { app.descendants(matching: .any)["\(identifierPrefix).error"] }

    /// Either terminal state, so one wait covers both instead of polling each.
    private var outcome: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["\(identifierPrefix).loaded", "\(identifierPrefix).error"]
        )).firstMatch
    }

    /// Fails fast with the app's own error text when the operation fails, rather than timing out.
    func waitUntilLoaded(
        _ description: String, timeout: TimeInterval = .uiWork,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard outcome.waitForExistence(timeout: timeout) else {
            XCTFail("\(description) never finished (still loading: \(loading.exists))", file: file, line: line)
            return
        }
        if error.exists {
            XCTFail("\(description) failed: \(error.label)", file: file, line: line)
        }
    }
}
