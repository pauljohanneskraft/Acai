import AcaiLibrary

/// The diagram kinds `acai_diagram` and `acai_image` render.
enum DiagramKind: String, CaseIterable {
    case `class`
    case package
    case sequence
    case state
    case callgraph
}

/// The three cuts of the static call graph `acai_callgraph` reports.
enum CallGraphMode: String, CaseIterable {
    case metrics
    case cycles
    case deadcode
}

/// The cycle scopes `acai_quality` lists in explore mode.
enum CycleScope: String, CaseIterable {
    case modules
    case types
    case all

    var finderScopes: [CycleFinder.Scope] {
        switch self {
        case .modules:
            [.modules]
        case .types:
            [.types]
        case .all:
            [.modules, .types]
        }
    }
}

/// The colour themes `acai_image` renders with.
enum ThemeOption: String, CaseIterable {
    case light
    case dark
}

extension EnumArgument where Option == TypeKind {
    static let kind = EnumArgument(
        name: "kind", description: "Only types of this declaration kind.")
}

extension EnumArgument where Option == AccessLevel {
    static let minimumAccess = EnumArgument(
        name: "minAccess", description: "Only types with at least this visibility.")
}

extension EnumArgument where Option == MemberKind {
    static let memberKind = EnumArgument(
        name: "memberKind", description: "Only members of this kind.")
}

extension EnumArgument where Option == DiagramKind {
    static let kind = EnumArgument(
        name: "kind", description: "Diagram kind (default class).")
}

extension EnumArgument where Option == DiagramFormat {
    static let format = EnumArgument(
        name: "format", description: "Output format (default mermaid).")
}

extension EnumArgument where Option == CallGraphMode {
    static let mode = EnumArgument(
        name: "mode", description: "What to report: metrics (default), cycles, or deadcode.")
}

extension EnumArgument where Option == CycleScope {
    static let scope = EnumArgument(
        name: "scope", description: "Cycle scope listed in explore mode (default all).")
}

extension EnumArgument where Option == ThemeOption {
    static let theme = EnumArgument(
        name: "theme", description: "Colour theme (default light).")
}
