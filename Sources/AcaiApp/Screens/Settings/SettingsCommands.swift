import SwiftUI

#if !os(macOS)
/// ⌘, on iPad/iPhone, matching what macOS's `Settings` scene provides on its own.
struct SettingsCommands: Commands {
    @EnvironmentObject private var presenter: SettingsPresenter

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button(.app("View.SettingsCommands.Settings")) {
                presenter.isPresented = true
            }
            .keyboardShortcut(.openSettings)
        }
    }
}
#endif
