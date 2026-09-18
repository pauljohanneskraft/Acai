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
    /// as its segments, not a custom identifier — and macOS exposes those segments as radio buttons
    /// (confirmed in a failing run's element tree), iOS as buttons.
    var settingsTabButton: XCUIElement { sidebarTab("Settings") }
    var inspectorTabButton: XCUIElement { sidebarTab("Inspector") }

    /// Matched by label without an identifier: the project browser's own `sidebar.settingsButton`
    /// carries the label "Settings" too, and a query matching both throws on every property read.
    private func sidebarTab(_ label: String) -> XCUIElement {
        let segments: XCUIElementQuery
        #if os(macOS)
        segments = app.radioButtons
        #else
        segments = app.buttons
        #endif
        return segments.matching(NSPredicate(format: "label == %@ AND identifier == ''", label)).firstMatch
    }
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
    /// so its absence then really means it's closed.
    private func openSidebarTab(
        _ tab: XCUIElement, content: XCUIElement, name: String, file: StaticString, line: UInt
    ) {
        if content.exists { return }
        if !settingsContent.exists && !inspectorContent.exists {
            tapSidebarToggle(file: file, line: line)
        }
        // Opening the sidebar restores the tab it was last on, which is usually this one already.
        if content.exists { return }
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

    /// Opens the Settings tab and scrolls until `element` is in the tree: the tab is a `Form`, which
    /// on iOS is a lazy `List` whose further-down rows don't exist until they scroll into view.
    func revealInSettings(
        _ element: XCUIElement, _ description: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        openSettingsTab(file: file, line: line)
        for _ in 0..<8 {
            if element.appears(within: .uiTransition / 8) { return }
            SystemBanners().dismiss(file: file, line: line)
            settingsContent.swipeUp()
        }
        element.waitOrFail(description, file: file, line: line)
    }

    /// Taps exactly once — every tap creates another copy — and waits for the copy to open.
    @discardableResult
    func saveAsFreeform(file: StaticString = #filePath, line: UInt = #line) -> FreeformDiagramScreen {
        revealInSettings(saveAsFreeformButton, "the Save as Freeform button", file: file, line: line)
        saveAsFreeformButton.tapWhenReady("Save as Freeform", file: file, line: line)
        settingsContent.waitForDisappearanceOrFail("the source diagram's Settings after saving", file: file, line: line)
        let freeform = FreeformDiagramScreen(app: app)
        freeform.openedIndicator.waitOrFail("the freeform copy", file: file, line: line)
        return freeform
    }

    #if os(iOS)
    var shareSheet: XCUIElement { app.descendants(matching: .any)["export.shareSheet"] }

    /// Taps exactly once and waits for the system share sheet the export hands its file to.
    @discardableResult
    func exportImage(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        revealInSettings(exportImageButton, "the Export Image button", file: file, line: line)
        exportImageButton.tapWhenReady("Export Image", file: file, line: line)
        return shareSheet.waitOrFail("the share sheet for the exported image", file: file, line: line)
    }
    #endif

    /// Falls back to iOS's "More" toolbar overflow item when the toolbar has collapsed the button into
    /// it — macOS's `NSToolbar` never collapses into overflow, so that branch is iOS/iPadOS-only. One
    /// query matching either element waits for whichever the toolbar rendered.
    /// With a `destination`, an overflow item is re-tapped only while its menu is still open — a tap
    /// landing while the menu is still presenting does nothing, and one that registered closes it.
    func tapToolbarButton(
        identifier: String, label: String, until destination: XCUIElement? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let button = app.buttons[identifier]
        #if os(macOS)
        button.tapWhenReady("toolbar button \(label)", file: file, line: line)
        #else
        let overflowIdentifier = "OverflowBarButtonItem"
        app.buttons.matching(NSPredicate(format: "identifier IN %@", [identifier, overflowIdentifier])).firstMatch
            .waitOrFail("toolbar button \(label), directly or in overflow", file: file, line: line)
        if button.exists {
            button.tapWhenReady("toolbar button \(label)", file: file, line: line)
            return
        }
        app.buttons[overflowIdentifier].tapWhenReady("the toolbar's overflow menu", file: file, line: line)
        if let destination {
            app.buttons[label].tap("overflow item \(label)", until: destination, file: file, line: line)
        } else {
            app.buttons[label].tapWhenReady("overflow item \(label)", file: file, line: line)
        }
        #endif
    }

    func tapFitToView(file: StaticString = #filePath, line: UInt = #line) {
        tapToolbarButton(identifier: "diagram.fitToViewButton", label: "Fit to View", file: file, line: line)
    }

    func tapSidebarToggle(file: StaticString = #filePath, line: UInt = #line) {
        tapToolbarButton(identifier: "diagram.sidebarToggleButton", label: "Sidebar", file: file, line: line)
    }

    // MARK: - Compare vs git (`CompareOverlayButton`/`CompareGitPanel`, shared by every diagram type)

    var compareButton: XCUIElement { app.descendants(matching: .any)["delta.openButton"] }
    /// No "None" row and no separate on/off toggle: tapping a row enables the diff against that ref
    /// directly; `compareClearButton` turns it back off. `name` matches `CompareGitPanel.RefRow.id`.
    func compareRefRow(_ name: String) -> XCUIElement { app.buttons["delta.ref.\(name)"] }
    var compareClearButton: XCUIElement { app.buttons["delta.clearButton"] }
    var compareCustomRefField: XCUIElement { app.descendants(matching: .any)["delta.customRefField"] }
    var compareOperation: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "delta") }
    var compareFindingsSummary: XCUIElement { app.descendants(matching: .any)["delta.findingsSummary"] }

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
