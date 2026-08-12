import Foundation

/// Whether the iPad/iPhone Settings sheet is presented — shared (like `QuickOpenPresenter`)
/// so a view other than `ProjectBrowserView` itself (specifically `NewCodebaseSheet`'s "Sign in to
/// GitHub in Settings" button, once signed out) can open it without needing a direct reference to
/// `ProjectBrowserView`'s own state. A no-op on macOS, which reaches Settings via the real `Settings`
/// scene (⌘,) instead — nothing sets this there, but it's harmless to have in the environment
/// regardless of platform so shared code (like `NewCodebaseSheet`) doesn't need `#if` branches just
/// to read it.
@MainActor
final class SettingsPresenter: ObservableObject {
    @Published var isPresented = false
}
