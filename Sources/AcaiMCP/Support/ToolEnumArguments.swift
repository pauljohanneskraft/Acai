import AcaiLibrary

/// The diagram kinds `acai_diagram` renders as text.
enum DiagramKind: String, ArgumentOption {
    case `class`
    case package
    case moduleCoupling
    case sequence
    case state
    case callgraph
}

/// The diagram kinds `acai_image` renders to a PNG — `moduleCoupling` has no image renderer, matching
/// `acai image`, which rejects `--module-coupling`.
enum ImageDiagramKind: String, ArgumentOption {
    case `class`
    case package
    case sequence
    case state
    case callgraph
}

/// The three cuts of the static call graph `acai_callgraph` reports.
enum CallGraphMode: String, ArgumentOption {
    case metrics
    case cycles
    case deadcode
}

/// The cycle scopes `acai_quality` lists in explore mode.
enum CycleScope: String, ArgumentOption {
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
enum ThemeOption: String, ArgumentOption {
    case light
    case dark
    /// Deprecated spelling of `light`; remove in the next major release, as the CLI's `--theme` does.
    case `default`

    static var advertisedCases: [ThemeOption] { [.light, .dark] }
}

extension TypeKind: ArgumentOption {}
extension AccessLevel: ArgumentOption {}
extension MemberKind: ArgumentOption {}
extension DiagramFormat: ArgumentOption {}

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

extension EnumArgument where Option == ImageDiagramKind {
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
