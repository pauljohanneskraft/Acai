import XCTest

@MainActor
final class KeyboardShortcutsScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var panel: XCUIElement { app.descendants(matching: .any)["keyboardShortcuts.panel"] }
    var doneButton: XCUIElement { app.buttons["keyboardShortcuts.doneButton"] }

    func close(file: StaticString = #filePath, line: UInt = #line) {
        doneButton.tapWhenReady("the Keyboard Shortcuts panel's Done button", file: file, line: line)
        panel.waitForDisappearanceOrFail("the Keyboard Shortcuts panel", file: file, line: line)
    }
}
