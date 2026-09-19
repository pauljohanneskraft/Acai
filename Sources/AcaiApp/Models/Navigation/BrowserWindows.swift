import Foundation

/// The app's open browser windows over the one shared store: which diagram each shows, which was
/// active last, and how to bring each to the front.
///
/// A diagram is shown by at most one window at a time: each window edits its own in-memory copy
/// (a freeform diagram's nodes and undo history), so a second copy would silently overwrite the first.
@MainActor
final class BrowserWindows: ObservableObject {
    @Published private(set) var diagramsByWindow: [UUID: UUID] = [:]
    /// Window-independent state (the store's error) is presented here only, not in every window.
    @Published private(set) var lastActiveWindow: UUID?
    private var focusActions: [UUID: () -> Void] = [:]

    func owner(of diagramID: UUID) -> UUID? {
        diagramsByWindow.first { $0.value == diagramID }?.key
    }

    func isOpenElsewhere(_ diagramID: UUID, from window: UUID) -> Bool {
        guard let owner = owner(of: diagramID) else { return false }
        return owner != window
    }

    /// `false` when another window already shows the diagram, which then keeps it.
    @discardableResult
    func claim(_ diagramID: UUID, for window: UUID) -> Bool {
        guard !isOpenElsewhere(diagramID, from: window) else {
            release(window)
            return false
        }
        if diagramsByWindow[window] != diagramID {
            diagramsByWindow[window] = diagramID
        }
        return true
    }

    func release(_ window: UUID) {
        guard diagramsByWindow[window] != nil else { return }
        diagramsByWindow.removeValue(forKey: window)
    }

    func windowOpened(_ window: UUID, focus: @escaping () -> Void) {
        focusActions[window] = focus
        if lastActiveWindow == nil { lastActiveWindow = window }
    }

    func windowBecameActive(_ window: UUID) {
        if lastActiveWindow != window { lastActiveWindow = window }
    }

    func windowClosed(_ window: UUID) {
        release(window)
        focusActions.removeValue(forKey: window)
        if lastActiveWindow == window { lastActiveWindow = focusActions.keys.first }
    }

    /// Brings the window showing `diagramID` to the front; `false` when no window shows it.
    @discardableResult
    func focusOwner(of diagramID: UUID) -> Bool {
        guard let owner = owner(of: diagramID), let focus = focusActions[owner] else { return false }
        focus()
        return true
    }
}
