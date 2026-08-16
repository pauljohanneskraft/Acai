/// Kept in sync by hand with the app's real `.keyboardShortcut(...)` call sites — only lists
/// shortcuts that actually exist.
struct KeyboardShortcutReference: Identifiable, Hashable {
    var id: String { context + symbol }
    var symbol: String
    var name: String
    var context: String
}

extension KeyboardShortcutReference {
    struct Group: Identifiable, Hashable {
        var id: String { title }
        var title: String
        var shortcuts: [KeyboardShortcutReference]
    }

    /// `⌘?` is macOS-only — iOS/iPadOS opens the panel from the sidebar toolbar instead.
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
