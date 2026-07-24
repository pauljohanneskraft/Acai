import CoreGraphics
import XCTest

/// Accessors for the chrome that's actually common across every diagram type's toolbar today
/// (`UndoRedoToolbarButtons`, Fit to View, the sidebar toggle) — see `TESTING_ARCHITECTURE.md`
/// Layer 2 for why this deliberately stays narrow rather than a full unified sidebar-tab base
/// class: `USABILITY_IMPROVEMENTS.md` Part 6 documents that today's diagram types have three
/// genuinely different sidebar architectures, so a shared Settings/Inspector/Compare accessor set
/// would encode a unification that hasn't shipped yet.
class DiagramScreenBase {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var undoButton: XCUIElement { app.buttons["diagram.undoButton"] }
    var redoButton: XCUIElement { app.buttons["diagram.redoButton"] }
    var fitToViewButton: XCUIElement { app.buttons["diagram.fitToViewButton"] }
    var sidebarToggleButton: XCUIElement { app.buttons["diagram.sidebarToggleButton"] }
    /// The inspector/sidebar's own "Done" button, shown only on compact width (iPhone), where
    /// `.inspector(isPresented:)` collapses to a plain sheet with no built-in dismiss chrome.
    var sidebarDoneButton: XCUIElement { app.buttons["diagram.sidebarDoneButton"] }
    /// Re-layout (Class Diagram only) / Configure (Call Graph, Sequence, State) — the type-specific
    /// configuration action each diagram toolbar has under a different label.
    var relayoutButton: XCUIElement { app.buttons["diagram.relayoutButton"] }
    var configureButton: XCUIElement { app.buttons["diagram.configureButton"] }
    var saveAsFreeformButton: XCUIElement { app.buttons["diagram.saveAsFreeformButton"] }
    var exportImageButton: XCUIElement { app.buttons["diagram.exportImageButton"] }
    /// The navigation bar's back button, for returning to `CodebaseDetailScreen` from a diagram.
    var backButton: XCUIElement { app.buttons["BackButton"] }

    /// A crowded toolbar (e.g. Class Diagram's Undo/Redo/Select/Re-layout/Fit-to-View/Save/Export)
    /// collapses trailing items into an iOS "More" overflow item on iPhone width, removing
    /// `fitToViewButton` from the directly-tappable bar entirely until "More" is opened first —
    /// and, once open, the revealed row only exposes its visible label ("Fit to View"), not the
    /// accessibility identifier (observed empirically), so the fallback matches by label.
    func tapFitToView() {
        if fitToViewButton.waitForExistence(timeout: 1) {
            fitToViewButton.tap()
            return
        }
        app.buttons["OverflowBarButtonItem"].tap()
        let overflowItem = app.buttons["Fit to View"]
        _ = overflowItem.waitForExistence(timeout: 5)
        overflowItem.tap()
    }

    // MARK: - Compare vs git (`CompareOverlayButton`/`CompareGitPanel`, shared by every diagram type)

    /// The floating button overlaid on the canvas; opens `CompareGitPanel` in a popover/sheet.
    var compareButton: XCUIElement { app.descendants(matching: .any)["delta.openButton"] }
    /// A row in the inline ref list (HEAD / each branch / each tag / Custom…) — no "None" row and
    /// no separate on/off toggle: tapping a row enables the diff against that ref directly;
    /// `compareClearButton` is what turns it back off. `name` matches `CompareGitPanel.RefRow.id`
    /// (e.g. `"HEAD"`, a branch/tag name, or `"custom"`).
    func compareRefRow(_ name: String) -> XCUIElement { app.buttons["delta.ref.\(name)"] }
    /// Nav-bar toolbar button; disables comparison directly (there's no "None" row to pick instead
    /// — see `CompareOverlayButton`'s own doc comment). Narrowed to `.buttons`, not the broad `.any`
    /// matcher the other accessors below use — a toolbar `Button`'s identifier matched more than
    /// one descendant node with `.any` (observed empirically), which `.buttons` disambiguates.
    var compareClearButton: XCUIElement { app.buttons["delta.clearButton"] }
    var compareCustomRefField: XCUIElement { app.descendants(matching: .any)["delta.customRefField"] }
    var compareLoadedIndicator: XCUIElement { app.descendants(matching: .any)["delta.loaded"] }
    var compareErrorIndicator: XCUIElement { app.descendants(matching: .any)["delta.error"] }

    /// Taps the floating Compare button to reveal `CompareGitPanel`'s popover/sheet, then waits for
    /// the HEAD row (always present) to appear — the panel's controls aren't in the accessibility
    /// tree at all until this opens it.
    func openCompare() {
        compareButton.tap()
        _ = compareRefRow("HEAD").waitForExistence(timeout: 5)
    }

    /// Taps the ref list row named `name` directly (e.g. `"HEAD"`, a branch/tag name, or `"none"`).
    @discardableResult
    func chooseCompareRef(_ name: String) -> XCUIElement {
        let row = compareRefRow(name)
        _ = row.waitForExistence(timeout: 5)
        row.tap()
        return row
    }
}
