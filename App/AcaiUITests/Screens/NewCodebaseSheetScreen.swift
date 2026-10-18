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

    // MARK: - A folder holding several projects

    var rootsHeader: XCUIElement { app.descendants(matching: .any)["newCodebase.rootsHeader"].firstMatch }
    var combineRootsToggle: XCUIElement {
        app.descendants(matching: .any)["newCodebase.combineRootsToggle"].firstMatch
    }

    /// One discovered root's checkbox, keyed by its path relative to the picked folder.
    func rootToggle(_ path: String) -> XCUIElement {
        app.descendants(matching: .any)["newCodebase.root.\(path)"].firstMatch
    }

    /// Picks the folder a UI test staged (`UITestFixtureResolver.resolveLocalFolderURL()`) — the
    /// system file importer the button otherwise presents can't be driven from here — and waits for
    /// the roots step.
    ///
    /// The step's own header is the wait's signal rather than a `rootDiscovery.loaded` marker: the
    /// plan is cleared before the walk starts and the header is rendered from its result, so the
    /// header cannot exist until the walk finished. The marker is only rendered while in flight,
    /// since a settled step showing "Loaded" under its own list would be noise.
    func chooseStagedFolder(file: StaticString = #filePath, line: UInt = #line) {
        chooseDirectoryButton.tapWhenReady("Choose…", file: file, line: line)
        rootsHeader.waitOrFail("the discovered-projects step", file: file, line: line)
    }

    /// On iOS the identified element is the whole row; a tap at its centre lands on the label and
    /// doesn't flip it, so tap the nested switch instead — as `ClassDiagramScreen.enableFocus` does.
    func flip(_ toggle: XCUIElement, _ description: String, file: StaticString = #filePath, line: UInt = #line) {
        #if os(macOS)
        let control = toggle
        #else
        let control = toggle.switches.firstMatch
        #endif
        control.tapWhenReady(description, file: file, line: line)
    }

    /// Confirms the sheet. The sheet dismisses as the codebases are created, so its disappearance is
    /// the completion signal; the caller asserts on the rows that appeared.
    func add(file: StaticString = #filePath, line: UInt = #line) {
        addButton.tapWhenReady("Add", file: file, line: line)
        addButton.waitForDisappearanceOrFail(
            "the Add Codebase sheet", failingOn: app.alerts.firstMatch, file: file, line: line)
    }

    /// Dismisses the sheet without adding anything. `.firstMatch` of a descendants query: a toolbar
    /// button's identifier resolves to more than one accessibility node.
    func cancel(file: StaticString = #filePath, line: UInt = #line) {
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: "newCodebase.cancelButton").firstMatch
        cancelButton.tapWhenReady("Cancel", file: file, line: line)
        cancelButton.waitForDisappearanceOrFail("the Add Codebase sheet", file: file, line: line)
    }

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

    /// The local-folder tab's own name field, which names the one codebase a combined add creates.
    func enterLocalName(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        localNameField.tapWhenReady("the codebase name field", file: file, line: line)
        localNameField.typeText(name + "\n")
        #if os(iOS)
        app.keyboards.firstMatch.waitForDisappearanceOrFail("the keyboard", file: file, line: line)
        #endif
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
