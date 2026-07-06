import UMLCore

// Design note — this is a deliberate *options bag*, not a long-parameter-list smell. Every field is an
// independently-defaulted toggle, and the `var`s exist so callers build it with a couple of labelled
// arguments (`ClassDiagramOptions(theme: .dark)`) and mutate the rest after the fact (the CLI does
// `options.theme = …` / `classFlags.apply(to: &options)`). No call site passes a long positional list,
// so grouping the initializer into sub-objects would only break ~30 construction + ~55 reader sites and
// worsen the common case for no real gain. The `maxParameters` metric measures this correctly; the
// judgement (per the audit's "tool measures, human judges" principle) is that the bag is the right shape.
public struct ClassDiagramOptions: Sendable {
    public var layoutDirection: LayoutDirection
    public var showMembers: Bool
    public var showMemberTypes: Bool
    public var showAccessLevelSymbols: Bool
    public var minimumAccessLevel: AccessLevel?
    public var includedRelationshipKinds: Set<Relationship.Kind>
    public var groupBy: GroupingStrategy
    public var showGenericParameters: Bool
    public var fontName: String
    public var fontSize: Int
    /// The cosmetic colour palette. `nil` emits structural output (no background, fill, border or
    /// font colours) so the consumer themes it at render time; set it for self-contained colours.
    /// Semantic colours (e.g. inferred edge labels) are unaffected.
    public var theme: DiagramTheme?

    // MARK: - Class-diagram enrichment options

    /// When `true`, properties whose declared type matches a known type produce
    /// composition / aggregation edges automatically.
    public var inferCompositionFromProperties: Bool

    /// When `true`, method parameter and return types that reference a known
    /// type produce dependency edges automatically.
    public var inferDependencyFromMethods: Bool

    /// When `true`, types referenced in relationships but not defined in the
    /// artifact are rendered as lightweight gray placeholder nodes.
    public var showExternalTypes: Bool

    /// When `true`, inferred association/aggregation/composition edges carry their
    /// `*` / `0..1` / `1` multiplicity labels (`headlabel`/`taillabel` in DOT).
    public var showMultiplicities: Bool

    /// When `true`, stereotypes derived from real type annotations (e.g. `@Entity`→`«entity»`)
    /// are emitted in addition to the kind-based stereotype. When `false`, only the
    /// `TypeKind` stereotype is shown.
    public var showAnnotationStereotypes: Bool

    /// When set, restricts the diagram to a single type and the slice of the
    /// relationship graph around it (see `FocusConfiguration`). `nil` renders the
    /// whole codebase.
    public var focus: FocusConfiguration?

    /// Resolves each type's language quirks (type-name classification + annotation stereotypes) from
    /// its own `sourceLanguage`, so a polyglot codebase is styled per type rather than under one
    /// artifact-wide language. Injected by the caller (`artifact.standardLanguageResolver`, or
    /// `LanguageConfigurationResolver(single:)` for a single-language render). Required — the diagram
    /// layer stays agnostic by receiving this rather than knowing any language, and the resolver's
    /// required default means there is no empty configuration to silently mis-classify into.
    public var languages: LanguageConfigurationResolver

    /// An optional per-edge colour override (a hex like `#2e7d32`). When it returns a non-`nil`
    /// colour for a relationship, that colour wins over `theme.edgeColor`; when it returns `nil`,
    /// or is itself `nil`, edge colouring is unchanged. Used to tint a delta diagram's added/
    /// removed/changed edges. Default `nil` keeps every existing diagram byte-for-byte identical.
    public var edgeColorOverride: (@Sendable (Relationship) -> String?)?

    /// An optional per-node fill override (a hex), the node counterpart of `edgeColorOverride`.
    /// When it returns a colour for a type, that fill wins over the theme; `nil` (or a `nil`
    /// closure) leaves the node unchanged. Used to tint a delta diagram's added/removed/changed
    /// type nodes.
    public var nodeColorOverride: (@Sendable (TypeDeclaration) -> String?)?

    public init(
        layoutDirection: LayoutDirection = .topToBottom,
        showMembers: Bool = true,
        showMemberTypes: Bool = true,
        showAccessLevelSymbols: Bool = true,
        minimumAccessLevel: AccessLevel? = nil,
        includedRelationshipKinds: Set<Relationship.Kind> = Set(Relationship.Kind.allCases),
        groupBy: GroupingStrategy = .none,
        showGenericParameters: Bool = true,
        fontName: String = "Helvetica",
        fontSize: Int = 12,
        theme: DiagramTheme? = nil,
        inferCompositionFromProperties: Bool = true,
        inferDependencyFromMethods: Bool = true,
        showExternalTypes: Bool = false,
        showMultiplicities: Bool = true,
        showAnnotationStereotypes: Bool = true,
        focus: FocusConfiguration? = nil,
        languages: LanguageConfigurationResolver,
        edgeColorOverride: (@Sendable (Relationship) -> String?)? = nil,
        nodeColorOverride: (@Sendable (TypeDeclaration) -> String?)? = nil
    ) {
        self.layoutDirection = layoutDirection
        self.showMembers = showMembers
        self.showMemberTypes = showMemberTypes
        self.showAccessLevelSymbols = showAccessLevelSymbols
        self.minimumAccessLevel = minimumAccessLevel
        self.includedRelationshipKinds = includedRelationshipKinds
        self.groupBy = groupBy
        self.showGenericParameters = showGenericParameters
        self.fontName = fontName
        self.fontSize = fontSize
        self.theme = theme
        self.inferCompositionFromProperties = inferCompositionFromProperties
        self.inferDependencyFromMethods = inferDependencyFromMethods
        self.showExternalTypes = showExternalTypes
        self.showMultiplicities = showMultiplicities
        self.showAnnotationStereotypes = showAnnotationStereotypes
        self.focus = focus
        self.languages = languages
        self.edgeColorOverride = edgeColorOverride
        self.nodeColorOverride = nodeColorOverride
    }

    public enum LayoutDirection: String, Sendable {
        case topToBottom = "TB"
        case bottomToTop = "BT"
        case leftToRight = "LR"
        case rightToLeft = "RL"
    }

    public enum GroupingStrategy: Sendable {
        case none
        case byFile
        case byNamespace
        /// Groups types by the directory of their source file.
        case byDirectory
    }
}

public struct DiagramTheme: Sendable {
    public var backgroundColor: String
    public var nodeFillColor: String
    public var nodeBorderColor: String
    public var fontColor: String
    public var edgeColor: String

    public init(
        backgroundColor: String,
        nodeFillColor: String,
        nodeBorderColor: String,
        fontColor: String,
        edgeColor: String
    ) {
        self.backgroundColor = backgroundColor
        self.nodeFillColor = nodeFillColor
        self.nodeBorderColor = nodeBorderColor
        self.fontColor = fontColor
        self.edgeColor = edgeColor
    }

    public static let `default` = DiagramTheme(
        backgroundColor: "white",
        nodeFillColor: "#f5f5f5",
        nodeBorderColor: "#333333",
        fontColor: "#333333",
        edgeColor: "#666666"
    )

    public static let dark = DiagramTheme(
        backgroundColor: "#1e1e1e",
        nodeFillColor: "#2d2d2d",
        nodeBorderColor: "#cccccc",
        fontColor: "#cccccc",
        edgeColor: "#999999"
    )

    /// A Mermaid init directive applying this palette through Mermaid's customizable `base`
    /// theme. Prepended as the first line of the diagram; a host that doesn't override it picks
    /// up these colours, while consumers that theme Mermaid themselves can drop the line.
    public func mermaidInit() -> String {
        "%%{init: {'theme':'base','themeVariables':{"
            + "'primaryColor':'\(nodeFillColor)',"
            + "'primaryBorderColor':'\(nodeBorderColor)',"
            + "'primaryTextColor':'\(fontColor)',"
            + "'lineColor':'\(edgeColor)',"
            + "'background':'\(backgroundColor)'"
            + "}}}%%"
    }
}
