import XCTest
#if os(macOS)
import AppKit
#endif

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
    var diagramThemePicker: XCUIElement { app.descendants(matching: .any)["settings.diagramThemePicker"] }
    /// iPad/iPhone only — macOS opens the shortcut reference from its menu bar.
    var keyboardShortcutsButton: XCUIElement { app.buttons["settings.keyboardShortcutsButton"] }
    var licensesLoad: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "licenses") }
    var licensesRetryButton: XCUIElement { app.buttons["licenses.retryButton"] }
    var licensesEmptyState: XCUIElement { app.descendants(matching: .any)["licenses.emptyState"] }

    #if os(macOS)
    /// The `Settings` scene takes its size from this pane, and a sheet presented over it centres on
    /// the window rather than on the display: a window taller than the screen puts its own
    /// confirmation's buttons below the visible area, where nothing can tap them. Heights rather
    /// than frames, so no assumption is made about which corner either coordinate space starts in.
    func assertWindowFitsTheScreen(file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.containing(.any, identifier: "settings.accountsPane").firstMatch
        window.waitOrFail("the Settings window", file: file, line: line)
        guard let visibleHeight = NSScreen.main?.visibleFrame.height else { return }
        XCTAssertLessThanOrEqual(
            window.frame.height, visibleHeight,
            "the Settings window must fit the screen, or a sheet it presents centres off-display",
            file: file, line: line
        )
    }
    #endif
}
