import XCTest

/// Accessors for Quick Open (`QuickOpenView`/`QuickOpenSheetHost`) — macOS's ⌘K, iPad's
/// pinned search field, and iPhone's dedicated search button all open the same sheet this covers.
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

    /// Types into the search field and waits past Quick Open's ~250ms debounce so a result row has
    /// actually had a chance to appear before a caller asserts on it.
    func search(_ text: String) {
        searchField.tap()
        searchField.typeText(text)
        Thread.sleep(forTimeInterval: 0.4)
    }
}
