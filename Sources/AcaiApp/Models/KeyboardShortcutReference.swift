/// One entry in the "Keyboard Shortcuts" reference panel (B56): a symbol, its action name, and the
/// context it applies in. Kept in sync by hand with the app's real `.keyboardShortcut(...)` call
/// sites — listing a shortcut here that isn't actually wired anywhere would be worse than not
/// having the panel at all, so this only lists shortcuts that exist today.
struct KeyboardShortcutReference: Identifiable, Hashable {
    var id: String { context + symbol }
    var symbol: String
    var name: String
    var context: String
}

extension KeyboardShortcutReference {
    /// A named section of the panel — one per context (canvas, undo, selection, …).
    struct Group: Identifiable, Hashable {
        var id: String { title }
        var title: String
        var shortcuts: [KeyboardShortcutReference]
    }

    /// Every shortcut currently wired up in the app, grouped for display. `⌘0` (fit to view) is
    /// shared by every diagram canvas (class, sequence, state, package, call graph, freeform); the
    /// rest are freeform-canvas-only. `⌘?` (this panel's own Help-menu shortcut) is macOS-only —
    /// iOS/iPadOS opens the panel from the sidebar toolbar instead, so it has no shortcut to list.
    static let groups: [Group] = {
        var groups: [Group] = [
            Group(title: "Canvas", shortcuts: [
                KeyboardShortcutReference(symbol: "⌘0", name: "Fit to View", context: "canvas")
            ]),
            Group(title: "Undo", shortcuts: [
                KeyboardShortcutReference(symbol: "⌘Z", name: "Undo", context: "undo"),
                KeyboardShortcutReference(symbol: "⇧⌘Z", name: "Redo", context: "undo")
            ]),
            Group(title: "Selection (Freeform Diagrams)", shortcuts: [
                KeyboardShortcutReference(symbol: "⌘C", name: "Copy", context: "selection"),
                KeyboardShortcutReference(symbol: "⌘X", name: "Cut", context: "selection"),
                KeyboardShortcutReference(symbol: "⌘V", name: "Paste", context: "selection"),
                KeyboardShortcutReference(symbol: "⌘A", name: "Select All", context: "selection"),
                KeyboardShortcutReference(symbol: "⌫", name: "Delete Selection", context: "selection")
            ])
        ]
        #if os(macOS)
        groups.append(Group(title: "Help", shortcuts: [
            KeyboardShortcutReference(symbol: "⌘?", name: "Keyboard Shortcuts", context: "help")
        ]))
        #endif
        return groups
    }()
}
