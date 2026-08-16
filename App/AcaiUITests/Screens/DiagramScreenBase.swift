import CoreGraphics
import XCTest

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
    /// Shown only on compact width (iPhone), where `.inspector(isPresented:)` collapses to a plain
    /// sheet with no built-in dismiss chrome.
    var sidebarDoneButton: XCUIElement { app.buttons["diagram.sidebarDoneButton"] }

    // MARK: - Sidebar tabs (every generated diagram type now has this Settings/Inspector split)

    /// A plain `Picker(selection:)` with `.pickerStyle(.segmented)` surfaces its `Text` case labels
    /// as buttons, not a custom identifier.
    var settingsTabButton: XCUIElement { app.buttons["Settings"] }
    var inspectorTabButton: XCUIElement { app.buttons["Inspector"] }
    var settingsContent: XCUIElement { app.descendants(matching: .any)["diagram.sidebarContent.settings"] }
    var inspectorContent: XCUIElement { app.descendants(matching: .any)["diagram.sidebarContent.inspector"] }

    /// Precondition for reaching `relayoutButton`/`configureButton`/`saveAsFreeformButton`/
    /// `exportImageButton`/any type-specific Settings control, all of which live in this tab.
    func openSettingsTab() {
        if !settingsContent.exists && !inspectorContent.exists {
            sidebarToggleButton.tap()
        }
        if !settingsContent.exists {
            settingsTabButton.tap()
        }
        _ = settingsContent.waitForExistence(timeout: 5)
    }

    /// Most journeys reach the Inspector by double-tapping a canvas element instead; this is for
    /// the cases that need it without an element to double-tap yet.
    func openInspectorTab() {
        if !settingsContent.exists && !inspectorContent.exists {
            sidebarToggleButton.tap()
        }
        if !inspectorContent.exists {
            inspectorTabButton.tap()
        }
        _ = inspectorContent.waitForExistence(timeout: 5)
    }

    /// Re-layout (Class Diagram) / entry-point-or-scope Apply (Sequence, State, Call Graph) — call
    /// `openSettingsTab()` first, these live in the Settings tab's `Form`, not the toolbar.
    var relayoutButton: XCUIElement { app.buttons["diagram.relayoutButton"] }
    var configureButton: XCUIElement { app.buttons["diagram.configureButton"] }
    var saveAsFreeformButton: XCUIElement { app.buttons["diagram.saveAsFreeformButton"] }
    var exportImageButton: XCUIElement { app.buttons["diagram.exportImageButton"] }
    var backButton: XCUIElement { app.buttons["BackButton"] }

    /// On Package Diagram/Call Graph screens only, `saveAsFreeformButton` opens a popover (macOS) or
    /// sheet (iOS/iPadOS) with this checkbox instead of saving immediately. `SwiftUI.Toggle` surfaces
    /// as a checkbox on macOS but a switch on iOS, hence the broad `.any` matcher.
    var saveAsFreeformIncludeMetricsToggle: XCUIElement {
        app.descendants(matching: .any)["diagram.saveAsFreeform.includeMetricsToggle"]
    }
    var saveAsFreeformConfirmButton: XCUIElement { app.buttons["diagram.saveAsFreeform.confirmButton"] }
    var saveAsFreeformCancelButton: XCUIElement { app.buttons["diagram.saveAsFreeform.cancelButton"] }

    /// Class/Sequence/State screens have no confirmation step — call `saveAsFreeformButton.tap()`
    /// directly there instead.
    func saveAsFreeform(includeMetricsNote: Bool) {
        saveAsFreeformButton.tap()
        _ = saveAsFreeformIncludeMetricsToggle.waitForExistence(timeout: 5)
        // The toggle only needs tapping when its current state doesn't already match the request.
        if let isOn = saveAsFreeformIncludeMetricsToggle.value as? String, (isOn == "1") != includeMetricsNote {
            saveAsFreeformIncludeMetricsToggle.tap()
        }
        saveAsFreeformConfirmButton.tap()
    }

    /// Falls back to iOS's "More" toolbar overflow item if `button` itself never appears — macOS's
    /// `NSToolbar` never collapses into overflow, so that branch is iOS/iPadOS-only.
    func tapToolbarButton(_ button: XCUIElement, label: String) {
        #if os(macOS)
        _ = button.waitForExistence(timeout: 10)
        button.tap()
        #else
        if button.waitForExistence(timeout: 10) {
            button.tap()
            return
        }
        let overflowButton = app.buttons["OverflowBarButtonItem"]
        guard overflowButton.waitForExistence(timeout: 2) else {
            return
        }
        overflowButton.tap()
        let overflowItem = app.buttons[label]
        _ = overflowItem.waitForExistence(timeout: 5)
        overflowItem.tap()
        #endif
    }

    func tapFitToView() {
        tapToolbarButton(fitToViewButton, label: "Fit to View")
    }

    // MARK: - Compare vs git (`CompareOverlayButton`/`CompareGitPanel`, shared by every diagram type)

    var compareButton: XCUIElement { app.descendants(matching: .any)["delta.openButton"] }
    /// No "None" row and no separate on/off toggle: tapping a row enables the diff against that ref
    /// directly; `compareClearButton` turns it back off. `name` matches `CompareGitPanel.RefRow.id`.
    func compareRefRow(_ name: String) -> XCUIElement { app.buttons["delta.ref.\(name)"] }
    var compareClearButton: XCUIElement { app.buttons["delta.clearButton"] }
    var compareCustomRefField: XCUIElement { app.descendants(matching: .any)["delta.customRefField"] }
    var compareLoadedIndicator: XCUIElement { app.descendants(matching: .any)["delta.loaded"] }
    var compareErrorIndicator: XCUIElement { app.descendants(matching: .any)["delta.error"] }
    var compareLoadingIndicator: XCUIElement { app.descendants(matching: .any)["delta.loading"] }

    /// The panel's controls aren't in the accessibility tree until this opens it.
    func openCompare() {
        compareButton.tap()
        _ = compareRefRow("HEAD").waitForExistence(timeout: 5)
    }

    @discardableResult
    func chooseCompareRef(_ name: String) -> XCUIElement {
        let row = compareRefRow(name)
        _ = row.waitForExistence(timeout: 5)
        row.tap()
        return row
    }
}
