import UMLCore

/// A member-level predicate, the companion to `Selector` (which is type-level). Every facet is
/// optional and AND-combined; a filter with no facets set matches every member. Naming no language,
/// it reads only the parsed member model.
public struct MemberFilter: Equatable, Sendable {
    /// Required member kind (e.g. `method`, `property`).
    public var kind: MemberKind?
    /// Minimum parameter count — finds wide signatures.
    public var minParameters: Int?
    /// Only publicly-settable stored properties (the `mutablePublicState` shape).
    public var isPublicVar: Bool?
    /// Only members that `override` an inherited member.
    public var isOverride: Bool?

    public init(
        kind: MemberKind? = nil,
        minParameters: Int? = nil,
        isPublicVar: Bool? = nil,
        isOverride: Bool? = nil
    ) {
        self.kind = kind
        self.minParameters = minParameters
        self.isPublicVar = isPublicVar
        self.isOverride = isOverride
    }

    /// Whether every present facet holds for `member`.
    public func matches(_ member: Member) -> Bool {
        if let kind, member.kind != kind { return false }
        if let minParameters, member.parameters.count < minParameters { return false }
        if let isPublicVar, member.isPubliclySettable != isPublicVar { return false }
        if let isOverride, member.modifiers.contains(.override) != isOverride { return false }
        return true
    }

    /// Whether any facet is set — when none is, the query keeps every member of a matched type.
    var isActive: Bool {
        kind != nil || minParameters != nil || isPublicVar != nil || isOverride != nil
    }
}

/// Enumerates the types (and their members) that satisfy a `Selector` + `MemberFilter`, tagged with
/// their `SourceLocation` for precise jump targets. A value you instantiate over an artifact
/// (`TypeQuery(artifact:selector:members:).rows`); the CLI's `inspect` command renders the rows and
/// downstream tooling (#104 worklist, #106 MCP) reuses them. Agnostic — `stereotype`/`annotation`
/// facets resolve against the injected `LanguageConfiguration` map.
public struct TypeQuery: Sendable {
    public struct TypeRow: Codable, Equatable, Sendable {
        public var id: String
        public var qualifiedName: String
        public var kind: TypeKind
        public var module: String
        public var access: AccessLevel
        public var stereotype: String?
        public var location: SourceLocation?
        public var members: [MemberRow]
    }

    public struct MemberRow: Codable, Equatable, Sendable {
        public var name: String
        public var kind: MemberKind
        public var access: AccessLevel
        public var parameterCount: Int
        public var location: SourceLocation?
    }

    private let artifact: CodeArtifact
    private let selector: Selector
    private let memberFilter: MemberFilter
    private let moduleResolver: ModuleResolver
    private let annotationStereotypes: [String: String]

    public init(
        artifact: CodeArtifact,
        selector: Selector = Selector(),
        members: MemberFilter = MemberFilter(),
        moduleResolver: ModuleResolver = .standard,
        annotationStereotypes: [String: String] = [:]
    ) {
        self.artifact = artifact
        self.selector = selector
        self.memberFilter = members
        self.moduleResolver = moduleResolver
        self.annotationStereotypes = annotationStereotypes
    }

    /// Matching types, each with its (filtered) members, sorted by qualified name. When the member
    /// filter is active, only types that keep at least one member are reported.
    public var rows: [TypeRow] {
        let graph = GraphView(
            artifact: artifact,
            moduleResolver: moduleResolver,
            annotationStereotypes: annotationStereotypes)
        return artifact.flattened().compactMap { type -> TypeRow? in
            guard let node = graph.node(id: type.id), selector.matches(node) else { return nil }
            let members = type.members.filter(memberFilter.matches)
            if memberFilter.isActive && members.isEmpty { return nil }
            return TypeRow(
                id: node.id,
                qualifiedName: node.qualifiedName,
                kind: node.kind,
                module: node.module,
                access: node.access,
                stereotype: node.stereotype,
                location: node.location,
                members: members.map { member in
                    MemberRow(
                        name: member.name,
                        kind: member.kind,
                        access: member.accessLevel,
                        parameterCount: member.parameters.count,
                        location: member.location)
                })
        }
        .sorted { $0.qualifiedName < $1.qualifiedName }
    }
}
