import SwiftUI

/// Every shortcut the app binds. Call sites pass one of these entries to `keyboardShortcut(_:)`, and
/// `KeyboardShortcutReferenceTests` rejects any other form, so the reference panel cannot omit one.
struct KeyboardShortcutReference: Identifiable, Sendable {
    /// Matches the `static let` name, which the guardrail test looks for at the call sites.
    let id: String
    let shortcut: KeyboardShortcut
    let name: LocalizedStringResource

    var symbol: String {
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        return text + keySymbol
    }

    private var keySymbol: String {
        switch shortcut.key {
        case .delete:
            "⌫"
        case .escape:
            "⎋"
        case .return:
            "↩"
        default:
            String(shortcut.key.character).uppercased()
        }
    }
}

extension KeyboardShortcutReference {
    static let fitToView = KeyboardShortcutReference(
        id: "fitToView", shortcut: KeyboardShortcut("0", modifiers: .command),
        name: .app("KeyboardShortcutReference.FitToView"))
    static let findInDiagram = KeyboardShortcutReference(
        id: "findInDiagram", shortcut: KeyboardShortcut("f", modifiers: .command),
        name: .app("KeyboardShortcutReference.FindInDiagram"))
    static let nextMatch = KeyboardShortcutReference(
        id: "nextMatch", shortcut: KeyboardShortcut("g", modifiers: .command),
        name: .app("KeyboardShortcutReference.NextMatch"))
    static let previousMatch = KeyboardShortcutReference(
        id: "previousMatch", shortcut: KeyboardShortcut("g", modifiers: [.command, .shift]),
        name: .app("KeyboardShortcutReference.PreviousMatch"))
    static let closeFind = KeyboardShortcutReference(
        id: "closeFind", shortcut: .cancelAction,
        name: .app("KeyboardShortcutReference.CloseFind"))
    static let undo = KeyboardShortcutReference(
        id: "undo", shortcut: KeyboardShortcut("z", modifiers: .command),
        name: .app("KeyboardShortcutReference.Undo"))
    static let redo = KeyboardShortcutReference(
        id: "redo", shortcut: KeyboardShortcut("z", modifiers: [.command, .shift]),
        name: .app("KeyboardShortcutReference.Redo"))
    static let copy = KeyboardShortcutReference(
        id: "copy", shortcut: KeyboardShortcut("c", modifiers: .command),
        name: .app("KeyboardShortcutReference.Copy"))
    static let cut = KeyboardShortcutReference(
        id: "cut", shortcut: KeyboardShortcut("x", modifiers: .command),
        name: .app("KeyboardShortcutReference.Cut"))
    static let paste = KeyboardShortcutReference(
        id: "paste", shortcut: KeyboardShortcut("v", modifiers: .command),
        name: .app("KeyboardShortcutReference.Paste"))
    static let selectAll = KeyboardShortcutReference(
        id: "selectAll", shortcut: KeyboardShortcut("a", modifiers: .command),
        name: .app("KeyboardShortcutReference.SelectAll"))
    static let deleteSelection = KeyboardShortcutReference(
        id: "deleteSelection", shortcut: KeyboardShortcut(.delete, modifiers: []),
        name: .app("KeyboardShortcutReference.DeleteSelection"))
    static let cancelPlacement = KeyboardShortcutReference(
        id: "cancelPlacement", shortcut: .cancelAction,
        name: .app("KeyboardShortcutReference.CancelPlacement"))
    static let confirmDialog = KeyboardShortcutReference(
        id: "confirmDialog", shortcut: .defaultAction,
        name: .app("KeyboardShortcutReference.ConfirmDialog"))
    static let cancelDialog = KeyboardShortcutReference(
        id: "cancelDialog", shortcut: .cancelAction,
        name: .app("KeyboardShortcutReference.CancelDialog"))
    static let quickOpen = KeyboardShortcutReference(
        id: "quickOpen", shortcut: KeyboardShortcut("k", modifiers: .command),
        name: .app("KeyboardShortcutReference.QuickOpen"))
    static let keyboardShortcuts = KeyboardShortcutReference(
        // Not ⇧⌘/: iPadOS keeps that for itself, and the Mac and iPad share one set of keys.
        id: "keyboardShortcuts", shortcut: KeyboardShortcut("/", modifiers: .command),
        name: .app("KeyboardShortcutReference.KeyboardShortcuts"))
}

extension KeyboardShortcutReference {
    struct Group: Identifiable, Sendable {
        let id: String
        let title: LocalizedStringResource
        let shortcuts: [KeyboardShortcutReference]
    }

    static let allGroups: [Group] = [
        Group(id: "canvas", title: .app("KeyboardShortcutReference.Canvas"), shortcuts: [.fitToView]),
        Group(
            id: "find", title: .app("KeyboardShortcutReference.FindClassDiagrams"),
            shortcuts: [.findInDiagram, .nextMatch, .previousMatch, .closeFind]),
        Group(id: "undo", title: .app("KeyboardShortcutReference.Undo"), shortcuts: [.undo, .redo]),
        Group(
            id: "selection", title: .app("KeyboardShortcutReference.SelectionFreeformDiagrams"),
            shortcuts: [.copy, .cut, .paste, .selectAll, .deleteSelection, .cancelPlacement]),
        Group(
            id: "dialogs", title: .app("KeyboardShortcutReference.Dialogs"),
            shortcuts: [.confirmDialog, .cancelDialog]),
        Group(id: "navigation", title: .app("KeyboardShortcutReference.Navigation"), shortcuts: [.quickOpen]),
        Group(id: "help", title: .app("KeyboardShortcutReference.Help"), shortcuts: [.keyboardShortcuts])
    ]
}

extension View {
    func keyboardShortcut(_ reference: KeyboardShortcutReference) -> some View {
        keyboardShortcut(reference.shortcut)
    }
}
