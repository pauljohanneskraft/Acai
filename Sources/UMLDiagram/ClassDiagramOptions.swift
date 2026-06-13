import UMLCore

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
    public var theme: DiagramTheme

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

    /// When set, restricts the diagram to a single type and the slice of the
    /// relationship graph around it (see `FocusConfiguration`). `nil` renders the
    /// whole codebase.
    public var focus: FocusConfiguration?

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
        theme: DiagramTheme = .default,
        inferCompositionFromProperties: Bool = true,
        inferDependencyFromMethods: Bool = true,
        showExternalTypes: Bool = false,
        focus: FocusConfiguration? = nil
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
        self.focus = focus
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
}
