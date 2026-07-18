import AcaiCore

/// A precomputed, queryable view of a `CodeArtifact` for conformance evaluation: every type
/// flattened and tagged with its module, stereotype, normalized annotations and metrics, plus the
/// relationship edges resolved to canonical ids. Built once and shared by all rules.
///
/// It is language-agnostic: the `ModuleResolver` and the annotation→stereotype map are injected by
/// the caller (the CLI resolves them from the artifact's `LanguageConfiguration`), so this names no
/// language or framework.
public struct GraphView: Sendable {
    /// A type node enriched with everything the rule selectors and budgets need.
    public struct Node: Sendable {
        public var id: String
        public var qualifiedName: String
        public var module: String
        public var kind: TypeKind
        public var access: AccessLevel
        public var stereotype: String?
        /// Normalized annotation markers (`@Entity` → `entity`).
        public var annotations: [String]
        public var location: SourceLocation?
        /// Declared member count (properties + methods + cases) — used by member-count selectors.
        public var memberCount: Int
        /// Depth of the nested-type tree rooted at this type — used by the `minNesting` selector.
        public var nestingDepth: Int
    }

    public let nodes: [Node]
    public let relationships: [Relationship]
    public let metrics: CodeMetrics

    private let nodesByID: [String: Node]

    public init(
        artifact: CodeArtifact,
        moduleResolver: ModuleResolver = .standard,
        languageResolver: LanguageConfigurationResolver
    ) {
        let flat = artifact.flattened()
        // Compute metrics up front so each node can be tagged with its metric-derived fields
        // (single source of truth — the node's `nestingDepth` comes from the metric, not a re-walk).
        let metrics = artifact.computeMetrics()
        let nestingByID = Dictionary(
            metrics.types.map { ($0.id, $0.nestingDepth) }, uniquingKeysWith: { first, _ in first })
        let nodes = flat.map { type in
            Node(
                id: type.id,
                qualifiedName: type.qualifiedName,
                module: moduleResolver.productName(forFilePath: type.location?.filePath ?? ""),
                kind: type.kind,
                access: type.accessLevel,
                stereotype: type.stereotype(
                    annotationStereotypes: languageResolver.configuration(for: type).annotationStereotypes),
                annotations: type.annotations.map(\.normalizedAnnotation),
                location: type.location,
                memberCount: type.members.count + type.enumCases.count,
                nestingDepth: nestingByID[type.id] ?? 0
            )
        }
        self.nodes = nodes
        self.relationships = artifact.relationships
        self.metrics = metrics
        self.nodesByID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The node for a canonical type id, or `nil` when the id is external to the codebase
    /// (e.g. a dependency on a third-party type that has no declaration here).
    public func node(id: String) -> Node? { nodesByID[id] }

    /// The set of modules that contain at least one node, sorted for deterministic reporting.
    public var moduleNames: [String] { Set(nodes.map(\.module)).sorted() }
}
