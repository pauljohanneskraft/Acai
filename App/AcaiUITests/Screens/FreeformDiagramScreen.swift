import XCTest

@MainActor
final class FreeformDiagramScreen: DiagramScreenBase {
    var checkpointsButton: XCUIElement { app.buttons["diagram.checkpointsButton"] }

    func tapCheckpoints() {
        tapToolbarButton(checkpointsButton, label: "Checkpoints")
    }

    func tapSidebarToggle() {
        tapToolbarButton(sidebarToggleButton, label: "Sidebar")
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

    func tapCanvasCenter() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// On regular width (iPad) the sidebar is a persistent `.inspector` column, and a canvas tap
    /// taken while it's still presented doesn't reach `InfiniteCanvas`'s tap gesture at all
    /// (confirmed empirically), so it must be closed before the commit tap — hence the two
    /// conditional toggles here rather than an unconditional open/close pair. On compact width
    /// (iPhone) the sidebar already auto-closes once placement begins, making the second toggle a
    /// no-op there. `"type.class"` (the catalog's first entry) stands in for "is the catalog
    /// showing at all," regardless of which `kindID` this call wants.
    func placeNodeViaCatalog(kindID: String) {
        if !catalogNodeButton("type.class").exists {
            tapSidebarToggle()
        }
        let button = catalogNodeButton(kindID)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "catalog entry '\(kindID)' never appeared")
        button.tap()
        XCTAssertTrue(cancelPlacementButton.waitForExistence(timeout: 5), "placement mode never started")
        if catalogNodeButton("type.class").exists {
            tapSidebarToggle()
        }
        tapCanvasCenter()
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

    func saveCheckpoint(named name: String) {
        tapCheckpoints()
        XCTAssertTrue(checkpointsSaveButton.waitForExistence(timeout: 5))
        checkpointsSaveButton.tap()
        XCTAssertTrue(checkpointsNameField.waitForExistence(timeout: 5))
        checkpointsNameField.clearAndTypeText(name)
        checkpointsConfirmSaveButton.tap()
    }
}
