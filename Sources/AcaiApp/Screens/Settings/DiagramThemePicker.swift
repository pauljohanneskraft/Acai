import SwiftUI

/// Shares its storage with `DiagramThemeCommands`, so Settings and macOS's View menu stay in sync.
struct DiagramThemePicker: View {
    @AppStorage(DiagramThemeSelection.storageKey, store: DiagramThemeSelection.store)
    private var selection: DiagramThemeSelection = .system

    var body: some View {
        Picker(.app("View.DiagramThemePicker.DiagramTheme"), selection: $selection) {
            ForEach(DiagramThemeSelection.allCases) { option in
                Label(option.label, systemImage: option.symbol).tag(option)
            }
        }
        .accessibilityIdentifier("settings.diagramThemePicker")
    }
}
