import XCTest

/// Kept separate from `GitHubAccountScreen`, which covers this tab's read-only signed-in summary /
/// "Open Settings" prompt (the actual sign-in UI moved to Settings).
@MainActor
final class NewCodebaseSheetScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var sourcePicker: XCUIElement { app.descendants(matching: .any)["newCodebase.sourcePicker"] }
    var localNameField: XCUIElement { app.textFields["newCodebase.localNameField"] }
    var chooseDirectoryButton: XCUIElement { app.buttons["newCodebase.chooseDirectoryButton"] }
    var addButton: XCUIElement { app.buttons["newCodebase.addButton"] }
    var repositoryPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.repositoryPicker"] }
    var refPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.refPicker"] }
    var cloneButton: XCUIElement { app.buttons["newCodebase.cloneButton"] }
    var cloneLoadingIndicator: XCUIElement { app.descendants(matching: .any)["newCodebase.clone.loading"] }

    @discardableResult
    func choose(_ label: String, from picker: XCUIElement, timeout: TimeInterval = 10) -> XCUIElement {
        picker.choose(label, in: app, timeout: timeout)
    }
}
