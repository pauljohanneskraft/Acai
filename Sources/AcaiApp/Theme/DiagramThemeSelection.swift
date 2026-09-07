import SwiftUI
import AcaiDiagram
import AcaiRender

/// The app-global diagram theme the user picks from the toolbar. It resolves to a
/// `DiagramPalette` for the on-screen canvases and to a `DiagramTheme` for DOT/Mermaid exports,
/// so one choice drives both. `system` follows the OS appearance.
enum DiagramThemeSelection: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// `UserDefaults` key shared by the `@AppStorage` binding and the (non-SwiftUI) export path.
    static let storageKey = "diagramTheme"

    /// The `UserDefaults` domain to read/write — `.standard` for real users, but an isolated suite
    /// scoped to the active UI test fixture's directory when one is active, so an automated test
    /// toggling the theme picker never reads or overwrites a real user's saved preference. Falls
    /// back to a still-isolated fixed suite name (never `.standard`) if the derived name is
    /// somehow rejected.
    static var store: UserDefaults {
        guard let baseDir = UITestFixtureResolver().resolveBaseDir() else { return .standard }
        let suiteName = "de.kraftsoftware.Acai.uitest.\(baseDir.lastPathComponent)"
        return UserDefaults(suiteName: suiteName)
            ?? UserDefaults(suiteName: "de.kraftsoftware.Acai.uitest.fallback")!
    }

    var label: LocalizedStringResource {
        switch self {
        case .system:
            .app("DiagramThemeSelection.System")
        case .light:
            .app("DiagramThemeSelection.Light")
        case .dark:
            .app("DiagramThemeSelection.Dark")
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

    static var current: DiagramThemeSelection {
        store.string(forKey: storageKey).flatMap(DiagramThemeSelection.init) ?? .system
    }

    static var currentExportTheme: DiagramTheme? {
        current.exportTheme
    }
}

/// Adds the global diagram-theme picker to the app's menu bar. `CommandGroup(after: .toolbar)`
/// places it inside macOS's built-in **View** menu (alongside Show Toolbar / Sidebar), so the theme
/// isn't an always-visible window control.
struct DiagramThemeCommands: Commands {
    @AppStorage(DiagramThemeSelection.storageKey, store: DiagramThemeSelection.store)
    private var selection: DiagramThemeSelection = .system

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Picker(.app("View.DiagramThemeCommands.DiagramTheme"), selection: $selection) {
                ForEach(DiagramThemeSelection.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

struct DiagramThemeProvider: ViewModifier {
    @AppStorage(DiagramThemeSelection.storageKey, store: DiagramThemeSelection.store)
    private var selection: DiagramThemeSelection = .system
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content.environment(\.diagramPalette, selection.palette(systemScheme: systemScheme))
    }
}
