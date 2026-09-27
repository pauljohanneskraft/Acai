import AcaiCore

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
    /// `nil` emits structural output (no background/fill/border/font colours) for the consumer to
    /// theme at render time.
    public var theme: DiagramTheme?

    // MARK: - Class-diagram enrichment options

    public var inferCompositionFromProperties: Bool
    public var inferDependencyFromMethods: Bool
    public var showExternalTypes: Bool
    public var showMultiplicities: Bool
    public var showAnnotationStereotypes: Bool
    public var focus: FocusConfiguration?
    /// Generation fails once the diagram would exceed this many nodes. `nil` means unlimited.
    public var maxNodes: Int?

    /// Resolves each type's language quirks from its own `sourceLanguage`, keeping this target
    /// agnostic to any specific language.
    public var languages: LanguageConfigurationResolver

    /// Wins over `theme.edgeColor` when non-`nil`.
    public var edgeColorOverride: (@Sendable (Relationship) -> String?)?
    /// The node counterpart of `edgeColorOverride`.
    public var nodeColorOverride: (@Sendable (TypeDeclaration) -> String?)?
    /// A line of text rendered under a node's name, so colour is never the only signal.
    public var nodeAnnotation: (@Sendable (TypeDeclaration) -> String?)?

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
        maxNodes: Int? = nil,
        languages: LanguageConfigurationResolver,
        edgeColorOverride: (@Sendable (Relationship) -> String?)? = nil,
        nodeColorOverride: (@Sendable (TypeDeclaration) -> String?)? = nil,
        nodeAnnotation: (@Sendable (TypeDeclaration) -> String?)? = nil
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
        self.maxNodes = maxNodes
        self.languages = languages
        self.edgeColorOverride = edgeColorOverride
        self.nodeColorOverride = nodeColorOverride
        self.nodeAnnotation = nodeAnnotation
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

    /// A Mermaid init directive applying this palette via Mermaid's `base` theme. Prepended as
    /// the diagram's first line; consumers that theme Mermaid themselves can drop it.
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
