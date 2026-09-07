import Foundation

/// Kept in sync by hand with the app's real `.keyboardShortcut(...)` call sites — only lists
/// shortcuts that actually exist.
struct KeyboardShortcutReference: Identifiable {
    var id: String { context + symbol }
    var symbol: String
    var name: LocalizedStringResource
    var context: String
}

extension KeyboardShortcutReference {
    struct Group: Identifiable {
        var id: String
        var title: LocalizedStringResource
        var shortcuts: [KeyboardShortcutReference]
    }

    /// `⌘?` is macOS-only — iOS/iPadOS opens the panel from the sidebar toolbar instead.
    static let groups: [Group] = {
        var groups: [Group] = [
            Group(id: "canvas", title: .app("KeyboardShortcutReference.Canvas"), shortcuts: [
                KeyboardShortcutReference(
                    symbol: "⌘0", name: .app("KeyboardShortcutReference.FitToView"), context: "canvas")
            ]),
            Group(id: "undo", title: .app("KeyboardShortcutReference.Undo"), shortcuts: [
                KeyboardShortcutReference(
                    symbol: "⌘Z", name: .app("KeyboardShortcutReference.Undo"), context: "undo"),
                KeyboardShortcutReference(
                    symbol: "⇧⌘Z", name: .app("KeyboardShortcutReference.Redo"), context: "undo")
            ]),
            Group(id: "selection", title: .app("KeyboardShortcutReference.SelectionFreeformDiagrams"), shortcuts: [
                KeyboardShortcutReference(
                    symbol: "⌘C", name: .app("KeyboardShortcutReference.Copy"), context: "selection"),
                KeyboardShortcutReference(
                    symbol: "⌘X", name: .app("KeyboardShortcutReference.Cut"), context: "selection"),
                KeyboardShortcutReference(
                    symbol: "⌘V", name: .app("KeyboardShortcutReference.Paste"), context: "selection"),
                KeyboardShortcutReference(
                    symbol: "⌘A", name: .app("KeyboardShortcutReference.SelectAll"), context: "selection"),
                KeyboardShortcutReference(
                    symbol: "⌫", name: .app("KeyboardShortcutReference.DeleteSelection"), context: "selection")
            ])
        ]
        #if os(macOS)
        groups.append(Group(id: "help", title: .app("KeyboardShortcutReference.Help"), shortcuts: [
            KeyboardShortcutReference(
                symbol: "⌘?", name: .app("KeyboardShortcutReference.KeyboardShortcuts"), context: "help")
        ]))
        #endif
        return groups
    }()
}
