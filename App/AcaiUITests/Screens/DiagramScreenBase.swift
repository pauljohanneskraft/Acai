import CoreGraphics
import XCTest

/// Accessors for the chrome common across every diagram type's toolbar today (`UndoRedoToolbarButtons`,
/// Fit to View, the sidebar toggle). Stays narrow rather than a unified sidebar-tab base class: the
/// diagram types have genuinely different sidebar architectures, so a shared Settings/Inspector/
/// Compare accessor set would encode a unification that hasn't shipped.
@MainActor
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

    /// A crowded toolbar collapses trailing items into an iOS "More" overflow item on iPhone width,
    /// removing a button from the directly-tappable bar until "More" is opened; the revealed row
    /// only exposes its visible `label`, not the accessibility identifier.
    func tapToolbarButton(_ button: XCUIElement, label: String) {
        if button.waitForExistence(timeout: 1) {
            button.tap()
            return
        }
        app.buttons["OverflowBarButtonItem"].tap()
        let overflowItem = app.buttons[label]
        _ = overflowItem.waitForExistence(timeout: 5)
        overflowItem.tap()
    }

    func tapFitToView() {
        tapToolbarButton(fitToViewButton, label: "Fit to View")
    }

    // MARK: - Compare vs git (`CompareOverlayButton`/`CompareGitPanel`, shared by every diagram type)

    /// The floating button overlaid on the canvas; opens `CompareGitPanel` in a popover/sheet.
    var compareButton: XCUIElement { app.descendants(matching: .any)["delta.openButton"] }
    /// A row in the inline ref list (HEAD / each branch / each tag / Custom…) — no "None" row and
    /// no separate on/off toggle: tapping a row enables the diff against that ref directly;
    /// `compareClearButton` is what turns it back off. `name` matches `CompareGitPanel.RefRow.id`
    /// (e.g. `"HEAD"`, a branch/tag name, or `"custom"`).
    func compareRefRow(_ name: String) -> XCUIElement { app.buttons["delta.ref.\(name)"] }
    /// Nav-bar toolbar button; disables comparison directly. Narrowed to `.buttons`, not the broad
    /// `.any` matcher the other accessors use — a toolbar `Button`'s identifier matches more than one
    /// descendant node under `.any`.
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
