import Testing
@testable import AcaiApp

/// `KeyboardShortcutReference` (B56): the data backing the "Keyboard Shortcuts" panel. Layer 0 —
/// checks internal consistency (no blank/duplicate entries). It does **not** and cannot verify the
/// panel's real invariant — that every listed shortcut matches an actual `.keyboardShortcut(...)`
/// call site and vice versa — since that would mean parsing every view in the app; that cross-check
/// is manual, done by hand against a `grep -rn ".keyboardShortcut("` whenever this list or a real
/// shortcut changes. `coversKnownShortcutsAsOfLastManualCheck` below pins the *current* hand-checked
/// set so an edit here is deliberate, not a silent drift from that manual check.
@Suite("Keyboard Shortcut Reference")
struct KeyboardShortcutReferenceTests {

    @Test("Every group has a non-empty title and at least one shortcut")
    func groupsAreWellFormed() {
        for group in KeyboardShortcutReference.groups {
            #expect(!group.title.isEmpty)
            #expect(!group.shortcuts.isEmpty)
        }
    }

    @Test("Every shortcut has a non-empty symbol and name")
    func shortcutsAreWellFormed() {
        for group in KeyboardShortcutReference.groups {
            for shortcut in group.shortcuts {
                #expect(!shortcut.symbol.isEmpty)
                #expect(!shortcut.name.isEmpty)
            }
        }
    }

    @Test("No two shortcuts collide on identity")
    func noDuplicateIDs() {
        let allIDs = KeyboardShortcutReference.groups.flatMap { $0.shortcuts.map(\.id) }
        #expect(Set(allIDs).count == allIDs.count)
    }

    /// Pins the set hand-verified against `grep -rn ".keyboardShortcut(" Sources/AcaiApp` as of B56
    /// landing: ⌘0 (fit to view), ⌘Z/⇧⌘Z (undo/redo), ⌘C/X/V/A (freeform selection), ⌫ (freeform
    /// delete), plus ⌘? (this panel's own Help-menu shortcut, macOS-only). A future edit to either
    /// side must update this test deliberately — it is a pin, not a live completeness check.
    @Test("The hand-verified shortcut set has not silently drifted")
    func coversKnownShortcutsAsOfLastManualCheck() {
        let allSymbols = Set(KeyboardShortcutReference.groups.flatMap { $0.shortcuts.map(\.symbol) })
        #if os(macOS)
        #expect(allSymbols == ["⌘0", "⌘Z", "⇧⌘Z", "⌘C", "⌘X", "⌘V", "⌘A", "⌫", "⌘?"])
        #else
        #expect(allSymbols == ["⌘0", "⌘Z", "⇧⌘Z", "⌘C", "⌘X", "⌘V", "⌘A", "⌫"])
        #endif
    }
}
