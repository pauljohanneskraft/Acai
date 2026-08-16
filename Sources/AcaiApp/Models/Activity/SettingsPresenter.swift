import Foundation

/// A no-op on macOS, which reaches Settings via the real `Settings` scene (⌘,) instead — nothing
/// sets this there, but it's harmless to have in the environment regardless of platform so shared
/// code doesn't need `#if` branches just to read it.
@MainActor
final class SettingsPresenter: ObservableObject {
    @Published var isPresented = false
}
