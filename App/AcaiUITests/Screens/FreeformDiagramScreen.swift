import XCTest

@MainActor
final class FreeformDiagramScreen: DiagramScreenBase {
    var checkpointsButton: XCUIElement { app.buttons["diagram.checkpointsButton"] }

    /// A control only this screen has, so it can't match the diagram a copy was saved from: the
    /// toolbar's Checkpoints button, or on compact width (where that may sit in the overflow menu)
    /// the bottom bar's mode picker.
    var openedIndicator: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["diagram.checkpointsButton", "diagram.bottomBar.modePicker"]
        )).firstMatch
    }

    func tapCheckpoints(file: StaticString = #filePath, line: UInt = #line) {
        tapToolbarButton(identifier: "diagram.checkpointsButton", label: "Checkpoints", file: file, line: line)
    }

    // MARK: - Point-and-Place Catalog

    /// A catalog entry, by its `FreeformDiagramNodeKind.id` (e.g. `"type.class"`, `"note"`) —
    /// tapping it enters placement mode rather than inserting immediately.
    func catalogNodeButton(_ kindID: String) -> XCUIElement {
        app.descendants(matching: .any)["catalog.nodeButton.\(kindID)"]
    }

    /// `.firstMatch`: this identifier bleeds down onto the ghost's own `Image`/`Text` children too.
    /// Not fixed on the production side — `.contain`/`.ignore` there crashed SwiftUI's
    /// AttributeGraph (confirmed via a real `EXC_BAD_ACCESS` in `AccessibilityAttachment`).
    var placementGhost: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "freeform.placementGhost").firstMatch
    }

    var cancelPlacementButton: XCUIElement { app.buttons["freeform.cancelPlacementButton"] }

    func tapCanvasCenter(file: StaticString = #filePath, line: UInt = #line) {
        SystemBanners().dismiss(file: file, line: line)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// On regular width the sidebar is a persistent `.inspector` column, and a canvas tap taken while
    /// it's still presented doesn't reach `InfiniteCanvas`'s tap gesture at all (confirmed
    /// empirically), so it must be closed before the commit tap. On compact width (iPhone) the sidebar
    /// closes itself once placement begins. The sidebar starts closed when a diagram opens and this
    /// leaves it closed, so it always opens it instead of branching on a not-yet-settled tree read.
    func placeNodeViaCatalog(kindID: String, file: StaticString = #filePath, line: UInt = #line) {
        tapSidebarToggle(file: file, line: line)
        let catalog = catalogNodeButton(kindID)
        catalog.tapWhenReady("catalog entry '\(kindID)'", file: file, line: line)
        cancelPlacementButton.waitOrFail("placement mode", file: file, line: line)
        if !SnapshotPlatform().usesCompactLayout {
            tapSidebarToggle(file: file, line: line)
        }
        catalog.waitForDisappearanceOrFail("the catalog sidebar", file: file, line: line)
        placementGhost.waitOrFail("the preview of the node about to be placed", file: file, line: line)
        tapCanvasCenter(file: file, line: line)
        placementGhost.waitForDisappearanceOrFail("the placement preview once placed", file: file, line: line)
    }

    /// `TypeNodeView` carries this identifier already (`diagram.typeNode.<name>`), same as
    /// `ClassDiagramScreen.typeNode`.
    func typeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.typeNode.\(name)"]
    }

    // MARK: - Checkpoints

    var checkpointsDoneButton: XCUIElement { app.buttons["checkpoints.doneButton"] }
    var checkpointsSaveButton: XCUIElement { app.buttons["checkpoints.saveButton"] }
    /// Matched by element kind, not identifier — confirmed empirically that a `TextField`'s
    /// identifier inside a SwiftUI `.alert` never reaches the native text field XCUITest sees
    /// (unlike the alert's own `Button`s). Platform-scoped because macOS renders `.alert` as a
    /// nested `Sheet` rather than an `Alert`, so `app.alerts[...]` never matches there.
    var checkpointsNameField: XCUIElement {
        #if os(macOS)
        app.sheets.textFields.firstMatch
        #else
        app.alerts["Save Checkpoint"].textFields.firstMatch
        #endif
    }
    var checkpointsConfirmSaveButton: XCUIElement {
        app.buttons.matching(identifier: "checkpoints.confirmSaveButton").firstMatch
    }

    func checkpointRow(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["checkpoints.row.\(name)"]
    }

    /// SwiftUI merges the row and its "Restore" `Button` into one accessibility element carrying
    /// the *row's* identifier, not `checkpoints.restoreButton.<name>` (confirmed empirically).
    func checkpointRestoreButton(named name: String) -> XCUIElement {
        app.buttons["checkpoints.row.\(name)"]
    }

    func saveCheckpoint(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        tapCheckpoints(file: file, line: line)
        checkpointsSaveButton.tapWhenReady("the checkpoints Save button", file: file, line: line)
        checkpointsNameField.waitOrFail("the checkpoint name field", file: file, line: line)
        checkpointsNameField.clearAndTypeText(name, file: file, line: line)
        checkpointsConfirmSaveButton.tapWhenReady("the checkpoint name alert's Save button", file: file, line: line)
    }
}
