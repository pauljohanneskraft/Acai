import CoreGraphics
import XCTest

@MainActor
class DiagramScreenBase {
    let app: XCUIApplication

    required init(app: XCUIApplication) {
        self.app = app
    }

    var undoButton: XCUIElement { app.buttons["diagram.undoButton"] }
    var redoButton: XCUIElement { app.buttons["diagram.redoButton"] }
    var fitToViewButton: XCUIElement { app.buttons["diagram.fitToViewButton"] }
    var sidebarToggleButton: XCUIElement { app.buttons["diagram.sidebarToggleButton"] }
    /// Shown only on compact width (iPhone), where `.inspector(isPresented:)` collapses to a plain
    /// sheet with no built-in dismiss chrome.
    var sidebarDoneButton: XCUIElement { app.buttons["diagram.sidebarDoneButton"] }

    // MARK: - Sidebar tabs (every generated diagram type has this Settings/Inspector split)

    /// A plain `Picker(selection:)` with `.pickerStyle(.segmented)` surfaces its `Text` case labels
    /// as buttons, not a custom identifier.
    var settingsTabButton: XCUIElement { app.buttons["Settings"] }
    var inspectorTabButton: XCUIElement { app.buttons["Inspector"] }
    var settingsContent: XCUIElement { app.descendants(matching: .any)["diagram.sidebarContent.settings"] }
    var inspectorContent: XCUIElement { app.descendants(matching: .any)["diagram.sidebarContent.inspector"] }

    /// Precondition for reaching `relayoutButton`/`configureButton`/`saveAsFreeformButton`/
    /// `exportImageButton`/any type-specific Settings control, all of which live in this tab.
    func openSettingsTab(file: StaticString = #filePath, line: UInt = #line) {
        openSidebarTab(settingsTabButton, content: settingsContent, name: "Settings", file: file, line: line)
    }

    /// Most journeys reach the Inspector by double-tapping a canvas element instead; this is for
    /// the cases that need it without an element to double-tap yet.
    func openInspectorTab(file: StaticString = #filePath, line: UInt = #line) {
        openSidebarTab(inspectorTabButton, content: inspectorContent, name: "Inspector", file: file, line: line)
    }

    /// Call once the diagram's canvas is confirmed on screen — the sidebar renders in the same pass,
    /// so its absence then really means it's closed. Selecting an already-selected segment is a no-op,
    /// so the tab is tapped unconditionally once the sidebar is open.
    private func openSidebarTab(
        _ tab: XCUIElement, content: XCUIElement, name: String, file: StaticString, line: UInt
    ) {
        if content.exists { return }
        if !settingsContent.exists && !inspectorContent.exists {
            tapToolbarButton(sidebarToggleButton, label: "Sidebar", file: file, line: line)
        }
        tab.tapWhenReady("the sidebar's \(name) tab", file: file, line: line)
        content.waitOrFail("the diagram's \(name) tab", file: file, line: line)
    }

    /// Re-layout (Class Diagram) / entry-point-or-scope Apply (Sequence, State, Call Graph) — call
    /// `openSettingsTab()` first, these live in the Settings tab's `Form`, not the toolbar.
    var relayoutButton: XCUIElement { app.buttons["diagram.relayoutButton"] }
    var configureButton: XCUIElement { app.buttons["diagram.configureButton"] }
    var saveAsFreeformButton: XCUIElement { app.buttons["diagram.saveAsFreeformButton"] }
    var exportImageButton: XCUIElement { app.buttons["diagram.exportImageButton"] }
    var backButton: XCUIElement { app.buttons["BackButton"] }

    /// Falls back to iOS's "More" toolbar overflow item if `button` itself never appears — macOS's
    /// `NSToolbar` never collapses into overflow, so that branch is iOS/iPadOS-only.
    func tapToolbarButton(
        _ button: XCUIElement, label: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(macOS)
        button.tapWhenReady("toolbar button \(label)", file: file, line: line)
        #else
        // Polls both together: on a toolbar that's already collapsed into "More", `button` was
        // never going to appear.
        let overflowButton = app.buttons["OverflowBarButtonItem"]
        let deadline = Date().addingTimeInterval(.uiTransition)
        while Date() < deadline, !button.exists, !overflowButton.exists {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if button.exists {
            button.tapWhenReady("toolbar button \(label)", file: file, line: line)
            return
        }
        overflowButton.tapWhenReady("toolbar button \(label), directly or in overflow", file: file, line: line)
        app.buttons[label].tapWhenReady("overflow item \(label)", file: file, line: line)
        #endif
    }

    func tapFitToView(file: StaticString = #filePath, line: UInt = #line) {
        tapToolbarButton(fitToViewButton, label: "Fit to View", file: file, line: line)
    }

    // MARK: - Compare vs git (`CompareOverlayButton`/`CompareGitPanel`, shared by every diagram type)

    var compareButton: XCUIElement { app.descendants(matching: .any)["delta.openButton"] }
    /// No "None" row and no separate on/off toggle: tapping a row enables the diff against that ref
    /// directly; `compareClearButton` turns it back off. `name` matches `CompareGitPanel.RefRow.id`.
    func compareRefRow(_ name: String) -> XCUIElement { app.buttons["delta.ref.\(name)"] }
    var compareClearButton: XCUIElement { app.buttons["delta.clearButton"] }
    var compareCustomRefField: XCUIElement { app.descendants(matching: .any)["delta.customRefField"] }
    var compareOperation: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "delta") }

    /// The panel's controls aren't in the accessibility tree until this opens it.
    func openCompare(file: StaticString = #filePath, line: UInt = #line) {
        compareButton.tap("the Compare button", until: compareRefRow("HEAD"), file: file, line: line)
    }

    /// Chooses `name` in the already-open compare panel and waits for the comparison to load.
    func compare(against name: String, timeout: TimeInterval = .uiWork, file: StaticString = #filePath, line: UInt = #line) {
        compareRefRow(name).tapWhenReady("compare ref row \(name)", file: file, line: line)
        compareOperation.waitUntilLoaded("Comparing against \(name)", timeout: timeout, file: file, line: line)
    }
}
