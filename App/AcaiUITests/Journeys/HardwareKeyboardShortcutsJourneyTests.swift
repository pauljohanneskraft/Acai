import XCTest

/// Every shortcut the Mac responds to also fires from an iPad's hardware keyboard. iPhone is skipped:
/// it has no hardware-keyboard parity requirement. Shortcuts bound on views are exercised by their
/// feature's journeys; these are the menu-command ones.
@MainActor
final class HardwareKeyboardShortcutsJourneyTests: UIJourneyTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipIf(SnapshotPlatform().usesCompactLayout, "Hardware-keyboard parity is an iPad and Mac concern")
    }

    func testQuickOpenOpensWithCommandK() {
        launchSeeded(analysis: .parsed).openQuickOpenWithKeyboard()
    }

    #if os(macOS)
    /// macOS only: iPadOS keeps ⇧⌘/ for itself — neither a menu command nor a view-bound shortcut
    /// receives it — so iPad lists the panel in its Help menu and reaches it from the sidebar.
    func testKeyboardShortcutsPanelOpensWithShiftCommandSlash() {
        launchSeeded().openKeyboardShortcutsWithKeyboard()
        KeyboardShortcutsScreen(app: app).close()
    }
    #else
    func testKeyboardShortcutsPanelOpensFromTheSidebarMenu() {
        launchSeeded().openKeyboardShortcutsFromMenu()
        KeyboardShortcutsScreen(app: app).close()
    }
    #endif
}
