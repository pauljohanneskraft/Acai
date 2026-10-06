import Foundation

/// Whether iPad/iPhone's Keyboard Shortcuts sheet is presented — shared so the ⌘/ menu command, which
/// lives outside the view hierarchy, can open it. macOS opens the panel as its own window instead.
@MainActor
final class KeyboardShortcutsPresenter: ObservableObject {
    @Published var isPresented = false
}
