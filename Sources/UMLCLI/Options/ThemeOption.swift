import ArgumentParser
import UMLDiagram

enum ThemeOption: String, ExpressibleByArgument, CaseIterable {
    case `default`
    case dark

    var diagramTheme: DiagramTheme {
        switch self {
        case .default:
            return .default
        case .dark:
            return .dark
        }
    }
}
