import SwiftUI
import UMLDiagram
import UMLRender

/// The app-global diagram theme the user picks from the toolbar. It resolves to a
/// `DiagramPalette` for the on-screen canvases and to a `DiagramTheme` for DOT/Mermaid exports,
/// so one choice drives both. `system` follows the OS appearance.
enum DiagramThemeSelection: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// `UserDefaults` key shared by the `@AppStorage` binding and the (non-SwiftUI) export path.
    static let storageKey = "diagramTheme"

    var label: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }

    /// The on-screen palette for this selection; `system` follows `systemScheme`.
    func palette(systemScheme: ColorScheme) -> DiagramPalette {
        switch self {
        case .system:
            .forScheme(systemScheme)
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    /// The theme baked into DOT / Mermaid exports for this selection. `system` exports
    /// *structural* output (no colours) so it stays deterministic and the consumer themes it;
    /// an explicit `light` / `dark` bakes that palette in.
    var exportTheme: DiagramTheme? {
        switch self {
        case .system:
            nil
        case .light:
            .default
        case .dark:
            .dark
        }
    }

    /// The current selection read straight from defaults, for call sites without a SwiftUI
    /// environment (e.g. the export view model).
    static var current: DiagramThemeSelection {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DiagramThemeSelection.init) ?? .system
    }

    /// The export theme for the current selection (`nil` for `system`).
    static var currentExportTheme: DiagramTheme? {
        current.exportTheme
    }
}

/// Adds the global diagram-theme picker to the app's menu bar. `CommandGroup(after: .toolbar)`
/// places it inside macOS's built-in **View** menu (alongside Show Toolbar / Sidebar), so the theme
/// isn't an always-visible window control.
struct DiagramThemeCommands: Commands {
    @AppStorage(DiagramThemeSelection.storageKey) private var selection: DiagramThemeSelection = .system

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Picker("Diagram Theme", selection: $selection) {
                ForEach(DiagramThemeSelection.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

/// Injects the selected theme's `DiagramPalette` into the environment for every diagram view,
/// and recolours when the OS appearance changes under the `system` option.
struct DiagramThemeProvider: ViewModifier {
    @AppStorage(DiagramThemeSelection.storageKey) private var selection: DiagramThemeSelection = .system
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content.environment(\.diagramPalette, selection.palette(systemScheme: systemScheme))
    }
}
