import XCTest

/// Accessors for the Freeform Diagram editor (`FreeformDiagramView`) — covers both
/// point-and-place insertion (catalog buttons, the placement ghost/cancel overlay, canvas taps) and
/// the checkpoints sheet (`FreeformDiagramCheckpointsView`). One screen object for both halves,
/// since this is the first (and only) screen object either needs.
@MainActor
final class FreeformDiagramScreen: DiagramScreenBase {
    var checkpointsButton: XCUIElement { app.buttons["diagram.checkpointsButton"] }

    /// Opens the Checkpoints sheet — falls back to iOS's "More" toolbar overflow via
    /// `tapToolbarButton`, same reasoning as `DiagramScreenBase.tapFitToView`.
    func tapCheckpoints() {
        tapToolbarButton(checkpointsButton, label: "Checkpoints")
    }

    /// Opens/closes the Node Catalog / Inspector sidebar — falls back to "More" overflow like
    /// `tapCheckpoints`.
    func tapSidebarToggle() {
        tapToolbarButton(sidebarToggleButton, label: "Sidebar")
    }

    // MARK: - Point-and-Place Catalog

    /// A catalog entry, by its `FreeformDiagramNodeKind.id` (e.g. `"type.class"`, `"note"`) —
    /// tapping it enters placement mode rather than inserting immediately.
    func catalogNodeButton(_ kindID: String) -> XCUIElement {
        app.descendants(matching: .any)["catalog.nodeButton.\(kindID)"]
    }

    /// The ghost preview that follows the cursor/touch while a placement is pending. `.firstMatch`:
    /// this identifier bleeds down onto the ghost's own `Image`/`Text` children too (no `.contain`/
    /// `.ignore` on the production side — that specific combination crashed SwiftUI's
    /// AttributeGraph, confirmed via a real `EXC_BAD_ACCESS` in `AccessibilityAttachment`, so this
    /// stays a test-side `.firstMatch` workaround instead).
    var placementGhost: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "freeform.placementGhost").firstMatch
    }

    /// The floating "Cancel Placement" HUD button, present only while a placement is pending.
    var cancelPlacementButton: XCUIElement { app.buttons["freeform.cancelPlacementButton"] }

    /// Taps the window's center to commit a pending placement (or clear the selection, if nothing is
    /// pending) — the same coordinate `handleBackgroundTap` reads via `cursorLocation`.
    func tapCanvasCenter() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Full point-and-place flow for a journey test: opens the sidebar (if not already open), taps
    /// `kindID`'s catalog entry (entering placement mode), closes the sidebar again, then taps the
    /// canvas to commit it. The close-before-tap step matters on regular width (iPad): there the
    /// sidebar is a persistent `.inspector` column rather than a sheet. Confirmed empirically (an
    /// accessibility-tree dump taken right after a plain canvas tap showed `pendingPlacement` still
    /// set, i.e. the tap never reached `InfiniteCanvas`'s tap gesture at all) that a canvas tap taken
    /// while the inspector is still presented doesn't commit the placement, and that closing the
    /// sidebar first resolves it. On compact width (iPhone) `FreeformDiagramView` already closes the
    /// sidebar itself the moment placement begins, so the guard here is a no-op there. The same
    /// asymmetry is why both toggles below are conditional, not unconditional: on iPad/macOS a second
    /// call in the same test (e.g. placing a second node) finds the sidebar already closed from the
    /// first call's cleanup, so toggling unconditionally would reopen it instead of closing it.
    /// `"type.class"` — always the catalog's first entry — stands in for "is the catalog showing at
    /// all" regardless of which `kindID` this particular call wants.
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

    /// A placed type node by its display name (e.g. `"NewClass"`) — `TypeNodeView` carries this
    /// identifier already (`diagram.typeNode.<name>`), same as `ClassDiagramScreen.typeNode`.
    func typeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.typeNode.\(name)"]
    }

    // MARK: - Checkpoints

    var checkpointsDoneButton: XCUIElement { app.buttons["checkpoints.doneButton"] }
    var checkpointsSaveButton: XCUIElement { app.buttons["checkpoints.saveButton"] }
    /// Matched by element kind, not `.accessibilityIdentifier("checkpoints.nameField")` — confirmed
    /// empirically (accessibility-tree dump) that a `TextField`'s identifier inside a SwiftUI
    /// `.alert` never reaches the native `UIAlertController`-backed text field XCUITest sees, unlike
    /// the alert's own `Button`s, whose identifiers do come through. There is only ever one text
    /// field in this alert, so matching by kind alone is unambiguous.
    ///
    /// Platform-scoped for the same reason `DeleteConfirmationTests` scopes its own dialog query:
    /// on iOS, SwiftUI's `.alert` renders as `XCUIElementType.Alert`, matched by `app.alerts[title]`.
    /// On macOS it instead renders as a nested `XCUIElementType.Sheet` (confirmed empirically —
    /// `Sheet, ..., label: 'alert', ...` — nested inside the Checkpoints sheet itself), so
    /// `app.alerts[...]` never matches there at all. Only one text field is ever showing across
    /// every sheet this app presents, so the unscoped-by-title `app.sheets.textFields.firstMatch` is
    /// still unambiguous.
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

    /// Confirmed empirically (accessibility-tree dump): the row and its "Restore" `Button` collapse
    /// into one accessibility element carrying the *row's* identifier (`checkpoints.row.<name>`),
    /// not the button's own `checkpoints.restoreButton.<name>` — SwiftUI merges a row with a single
    /// interactive child into one element here. Matching on the row's identifier (already scoped to
    /// `.buttons` since the merged element reports as a Button) is what's actually tappable.
    func checkpointRestoreButton(named name: String) -> XCUIElement {
        app.buttons["checkpoints.row.\(name)"]
    }

    /// Opens the Checkpoints sheet, saves a new checkpoint named `name` (clearing the
    /// timestamp-prefilled default first), and leaves the sheet open for further assertions/actions.
    func saveCheckpoint(named name: String) {
        tapCheckpoints()
        XCTAssertTrue(checkpointsSaveButton.waitForExistence(timeout: 5))
        checkpointsSaveButton.tap()
        XCTAssertTrue(checkpointsNameField.waitForExistence(timeout: 5))
        checkpointsNameField.clearAndTypeText(name)
        checkpointsConfirmSaveButton.tap()
    }
}
