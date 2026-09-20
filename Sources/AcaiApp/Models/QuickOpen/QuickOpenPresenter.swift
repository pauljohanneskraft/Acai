import Foundation

/// Whether a window's Quick Open sheet is presented. On macOS each `ProjectBrowserView` owns one and
/// publishes it as a focused scene object, so ⌘L (`QuickOpenCommands`) opens it in the key window
/// only. iOS has a single scene, so `AcaiRootScene` owns the one presenter and injects it as an
/// environment object, the same way `KeyboardShortcutsPresenter` reaches its menu command.
@MainActor
final class QuickOpenPresenter: ObservableObject {
    @Published var isPresented = false
}
