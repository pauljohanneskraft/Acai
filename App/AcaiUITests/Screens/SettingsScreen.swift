import XCTest

@MainActor
final class SettingsScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// The iPad/iPhone sheet's root container.
    var sheet: XCUIElement { app.descendants(matching: .any)["settings.sheet"] }
    /// macOS's `Settings` scene pane.
    var accountsPane: XCUIElement { app.descendants(matching: .any)["settings.accountsPane"] }
    var doneButton: XCUIElement { app.buttons["settings.doneButton"] }
}
