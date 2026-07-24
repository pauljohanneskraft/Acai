import XCTest

/// Accessors for `NewCodebaseSheet`'s GitHub tab — the repository/branch pickers and the Clone
/// action. Kept separate from `GitHubAccountScreen` (embedded inside this same sheet), which stays
/// scoped to the sign-in section it wraps. See `TESTING_ARCHITECTURE.md` Layer 2.
final class NewCodebaseSheetScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var sourcePicker: XCUIElement { app.descendants(matching: .any)["newCodebase.sourcePicker"] }
    var localNameField: XCUIElement { app.textFields["newCodebase.localNameField"] }
    var chooseDirectoryButton: XCUIElement { app.buttons["newCodebase.chooseDirectoryButton"] }
    /// A plain (non-`.plain`-styled) toolbar button — `app.buttons[...]`, like `cloneButton` below,
    /// resolves to the single real `Button` element without the wrapping bar-item container's
    /// duplicate match (`app.descendants(matching: .any)` would hit both).
    var addButton: XCUIElement { app.buttons["newCodebase.addButton"] }
    var repositoryPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.repositoryPicker"] }
    var refPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.refPicker"] }
    var cloneButton: XCUIElement { app.buttons["newCodebase.cloneButton"] }

    /// Picks a repository/ref from their respective `Picker`s — see `XCUIElement.choose(_:in:timeout:)`
    /// for why this matches by literal text rather than a per-option identifier.
    @discardableResult
    func choose(_ label: String, from picker: XCUIElement, timeout: TimeInterval = 10) -> XCUIElement {
        picker.choose(label, in: app, timeout: timeout)
    }
}
