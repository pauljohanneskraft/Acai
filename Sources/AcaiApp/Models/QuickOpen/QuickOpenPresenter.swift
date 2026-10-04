import Foundation

/// Whether a window's Quick Open sheet is presented. On macOS each `ProjectBrowserView` owns one and
/// publishes it as a focused scene object, so ⇧⌘O (`QuickOpenCommands`) opens it in the key window
/// only. iOS has a single window, so `AcaiRootScene` owns the one presenter and injects it as an
/// environment object — which `QuickOpenCommands` can read, where a view's `@StateObject` could not.
@MainActor
final class QuickOpenPresenter: ObservableObject {
    @Published var isPresented = false
}
