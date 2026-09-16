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

    /// Taps Clone and waits for the whole operation — clone *and* the first index — to finish. The
    /// sheet dismisses exactly then, so its `newCodebase.clone.loaded` state is never observable and
    /// the new codebase's row appears before indexing is done; the dismissal is the completion signal.
    /// A failure surfaces as the app's error alert, reported immediately instead of timing out.
    func clone(file: StaticString = #filePath, line: UInt = #line) {
        cloneButton.tapWhenReady("Clone", file: file, line: line)
        let deadline = Date().addingTimeInterval(.uiWork)
        while Date() < deadline {
            if cloneButton.waitForNonExistence(timeout: 5) { return }
            if app.alerts.firstMatch.exists {
                XCTFail("cloning failed: \(app.alerts.firstMatch.label)", file: file, line: line)
                return
            }
        }
        XCTFail("the clone never finished (still cloning: \(cloneLoadingIndicator.exists))", file: file, line: line)
    }

    @discardableResult
    func choose(
        _ label: String, from picker: XCUIElement, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        picker.choose(label, in: app, timeout: timeout, file: file, line: line)
    }
}
