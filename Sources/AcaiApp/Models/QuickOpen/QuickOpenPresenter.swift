import Foundation

/// Whether Quick Open's sheet is presented — a tiny piece of shared state instantiated once
/// in `AcaiRootScene` and injected into both the main `WindowGroup` and macOS's `.commands` block,
/// since a `Commands` menu item lives outside the view hierarchy `ProjectBrowserView`'s own
/// `@State` could reach directly. `QuickOpenCommands` toggles this to open ⌘K; `ProjectBrowserView`
/// binds its Quick Open sheet to it on every platform.
@MainActor
final class QuickOpenPresenter: ObservableObject {
    @Published var isPresented = false
}
