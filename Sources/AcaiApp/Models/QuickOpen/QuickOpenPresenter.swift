import Foundation

/// Whether one window's Quick Open sheet is presented. Each `ProjectBrowserView` owns one and
/// publishes it as a focused scene object, so macOS's ⌘K (`QuickOpenCommands`) opens it in the key
/// window only. iPad has no menu command to reach — its ⌘K is bound on the toolbar button that sets
/// this directly.
@MainActor
final class QuickOpenPresenter: ObservableObject {
    @Published var isPresented = false
}
