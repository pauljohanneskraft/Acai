import XCTest

/// Accessors for the Settings surface — macOS's `Settings` scene (`SettingsView`) and iPad/
/// iPhone's `SettingsSheet`, both hosting the same `GitHubAccountSection` content
/// (`GitHubAccountScreen` covers that content itself; this covers the surrounding chrome).
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
