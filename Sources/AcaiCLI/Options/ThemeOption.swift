import ArgumentParser
import AcaiDiagram

enum ThemeOption: String, ExpressibleByArgument, CaseIterable {
    case light
    case dark
    /// Deprecated alias for `light`, hidden from `--help` so no existing script breaks. Remove in the
    /// next major release.
    case `default`

    static var allValueStrings: [String] { [Self.light.rawValue, Self.dark.rawValue] }

    var diagramTheme: DiagramTheme {
        switch self {
        case .light, .default:
            return .default
        case .dark:
            return .dark
        }
    }
}
