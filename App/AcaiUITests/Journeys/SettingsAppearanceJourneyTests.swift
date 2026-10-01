import XCTest

/// The diagram theme lives in Settings on every platform, and on iPad/iPhone so does the keyboard
/// shortcut reference — neither has room in the sidebar's bar. iPad and Mac also open the reference with ⌘/.
@MainActor
final class SettingsAppearanceJourneyTests: UIJourneyTestCase {
    func testSettingsOffersTheDiagramTheme() throws {
        let browser = launchSeeded(analysis: .parsed)
        if !SnapshotPlatform().usesCompactLayout {
            browser.openKeyboardShortcutsWithKeyboard()
            KeyboardShortcutsScreen(app: app).close()
        }
        browser.openSettings()

        let settings = SettingsScreen(app: app)
        settings.diagramThemePicker.waitOrFail("the diagram theme picker in Settings")
        #if os(iOS)
        settings.keyboardShortcutsButton.tap(
            "Keyboard Shortcuts", until: app.navigationBars["Keyboard Shortcuts"])
        #endif
    }
}
