import Testing
@testable import AcaiApp

/// `KeyboardShortcutReference` backs the "Keyboard Shortcuts" panel. These checks cover internal
/// consistency (no blank/duplicate entries) — they cannot verify every listed shortcut matches a
/// real `.keyboardShortcut(...)` call site, since that would mean parsing every view; that
/// cross-check is manual (`grep -rn ".keyboardShortcut("`) whenever this list or a shortcut changes.
/// `coversKnownShortcutsAsOfLastManualCheck` pins the hand-checked set so drift here is deliberate.
@Suite("Keyboard Shortcut Reference")
struct KeyboardShortcutReferenceTests {

    @Test("Every group has a non-empty title and at least one shortcut")
    func groupsAreWellFormed() {
        for group in KeyboardShortcutReference.groups {
            #expect(!String(localized: group.title).isEmpty)
            #expect(!group.shortcuts.isEmpty)
        }
    }

    @Test("Every shortcut has a non-empty symbol and name")
    func shortcutsAreWellFormed() {
        for group in KeyboardShortcutReference.groups {
            for shortcut in group.shortcuts {
                #expect(!shortcut.symbol.isEmpty)
                #expect(!String(localized: shortcut.name).isEmpty)
            }
        }
    }

    @Test("No two shortcuts collide on identity")
    func noDuplicateIDs() {
        let allIDs = KeyboardShortcutReference.groups.flatMap { $0.shortcuts.map(\.id) }
        #expect(Set(allIDs).count == allIDs.count)
    }

    /// Pins the set hand-verified against `grep -rn ".keyboardShortcut(" Sources/AcaiApp`: ⌘0 (fit
    /// to view), ⌘Z/⇧⌘Z (undo/redo), ⌘C/X/V/A (freeform selection), ⌫ (freeform delete), plus ⌘?
    /// (this panel's own Help-menu shortcut, macOS-only). Not a live completeness check.
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
