import XCTest

@MainActor
final class QuickOpenScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var searchField: XCUIElement { app.textFields["quickOpen.searchField"] }
    var loadingState: XCUIElement { app.descendants(matching: .any)["quickOpen.loadingState"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["quickOpen.emptyState"] }
    var noResultsState: XCUIElement { app.descendants(matching: .any)["quickOpen.noResultsState"] }
    var cancelButton: XCUIElement { app.buttons["quickOpen.cancelButton"] }

    /// `id` is a `QuickOpenEntry.id` (e.g. `"type:MyModule.MyType"`).
    func result(id: String) -> XCUIElement {
        app.descendants(matching: .any)["quickOpen.result.\(id)"]
    }

    /// Types `text` and waits for `expected`, retyping if it never arrives. Quick Open re-filters on
    /// query *changes* only, so a query landing before the index finished building filters an empty
    /// list and never re-runs — retyping is what recovers from that, which a plain wait can't do.
    @discardableResult
    func search(_ text: String, until expected: XCUIElement, attempts: Int = 3, timeout: TimeInterval = 5) -> Bool {
        for _ in 0..<attempts {
            searchField.clearAndTypeText(text)
            if expected.waitForExistence(timeout: timeout) { return true }
        }
        return false
    }
}
