import Foundation

/// Whether a window's Quick Open sheet is presented. On macOS each `ProjectBrowserView` owns one and
/// publishes it as a focused scene object, so ⌘K (`QuickOpenCommands`) opens it in the key window
/// only. iOS has a single scene, and its focused-scene objects reach the key-command system late
/// enough on a slow device that a ⌘K typed right after launch is lost — there `AcaiRootScene` owns
/// the one presenter and injects it as an environment object, which is in place from the first frame.
@MainActor
final class QuickOpenPresenter: ObservableObject {
    @Published var isPresented = false
}
