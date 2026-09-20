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
    /// The GitHub tab's optional name override — distinct from `localNameField`, the Local Folder
    /// tab's own name field.
    var nameField: XCUIElement { app.textFields["newCodebase.nameField"] }
    var chooseDirectoryButton: XCUIElement { app.buttons["newCodebase.chooseDirectoryButton"] }
    var addButton: XCUIElement { app.buttons["newCodebase.addButton"] }
    var repositoryPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.repositoryPicker"] }
    var refPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.refPicker"] }
    var cloneButton: XCUIElement { app.buttons["newCodebase.cloneButton"] }
    var remoteAddressField: XCUIElement { app.textFields["newCodebase.remoteAddressField"] }
    var remoteRefsOperation: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "newCodebase.remoteRefs") }
    var cloneLatestSnapshotButton: XCUIElement {
        app.buttons["newCodebase.largeClone.latestSnapshotButton"].firstMatch
    }
    var cloneFullHistoryButton: XCUIElement { app.buttons["newCodebase.largeClone.fullHistoryButton"].firstMatch }

    /// `source` is the segment's `NewCodebaseSheet.Source` raw value. Segments surface as different
    /// element kinds on macOS (`NSSegmentedControl`) and iOS, and not every one carries the segment
    /// label's identifier, so the English label is matched as well.
    func sourceSegment(_ source: String, label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "newCodebase.source.\(source)", label
        )).firstMatch
    }

    func selectRemoteURLSource(file: StaticString = #filePath, line: UInt = #line) {
        sourceSegment("remoteURL", label: "Remote URL").tap(
            "the Remote URL source", until: remoteAddressField, file: file, line: line)
    }

    /// Types the address and waits for the remote's branches, which are read without cloning.
    func enterRemoteAddress(_ address: String, file: StaticString = #filePath, line: UInt = #line) {
        remoteAddressField.tapWhenReady("the remote address field", file: file, line: line)
        remoteAddressField.typeText(address + "\n")
        #if os(iOS)
        app.keyboards.firstMatch.waitForDisappearanceOrFail("the keyboard", file: file, line: line)
        #endif
        remoteRefsOperation.waitUntilLoaded("Reading the remote's branches", file: file, line: line)
    }

    /// A clone the large-repository warning intercepted: answering it starts the clone, and the
    /// sheet dismisses once cloning and the first index are done.
    func answerLargeCloneWarning(
        with choice: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        cloneButton.tapWhenReady("Clone", file: file, line: line)
        choice.tapWhenReady("the large-repository choice", file: file, line: line)
        cloneButton.waitForDisappearanceOrFail(
            "the Add Codebase sheet (cloning and indexing)", failingOn: app.alerts.firstMatch, file: file, line: line
        )
    }
    var cloneLoadingIndicator: XCUIElement { app.descendants(matching: .any)["newCodebase.clone.loading"] }

    /// Taps Clone and waits for the whole operation — clone *and* the first index — to finish. The
    /// sheet dismisses exactly then, so its `newCodebase.clone.loaded` state is never observable and
    /// the new codebase's row appears before indexing is done; the dismissal is the completion signal.
    /// A failure surfaces as the app's error alert, reported immediately instead of timing out.
    func clone(file: StaticString = #filePath, line: UInt = #line) {
        cloneButton.tapWhenReady("Clone", file: file, line: line)
        cloneButton.waitForDisappearanceOrFail(
            "the Add Codebase sheet (cloning and indexing)", failingOn: app.alerts.firstMatch, file: file, line: line
        )
    }

    /// Submits with Return so the iPad keyboard, which covers the pickers below the field, goes away.
    func enterName(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        nameField.tapWhenReady("the codebase name field", file: file, line: line)
        nameField.typeText(name + "\n")
        #if os(iOS)
        app.keyboards.firstMatch.waitForDisappearanceOrFail("the keyboard", file: file, line: line)
        #endif
    }

    @discardableResult
    func choose(
        _ label: String, from picker: XCUIElement, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        picker.choose(label, in: app, timeout: timeout, file: file, line: line)
    }
}
