/// The blast radius of a type: every type that (transitively) depends on it — the reverse-reachability
/// slice of the relationship graph. Answers "what could break if I change this?" as a count plus the
/// list of dependents with `file:line`. A value you instantiate over an artifact
/// (`ImpactAnalysis(artifact:rootType:).report`), wrapping `CodeArtifact.focusedSubset` with
/// `direction: .dependents`.
public struct ImpactAnalysis: Sendable {
    /// One type that depends on the root.
    public struct Dependent: Codable, Equatable, Sendable {
        public var id: String
        public var qualifiedName: String
        public var location: SourceLocation?
    }

    public struct Report: Codable, Equatable, Sendable {
        public var root: String
        /// `false` when the root name couldn't be resolved to a declared type.
        public var found: Bool
        /// Number of transitive dependents.
        public var blastRadius: Int
        public var dependents: [Dependent]
    }

    private let artifact: CodeArtifact
    private let rootType: String
    private let maxDepth: Int?

    public init(artifact: CodeArtifact, rootType: String, maxDepth: Int? = nil) {
        self.artifact = artifact
        self.rootType = rootType
        self.maxDepth = maxDepth
    }

    public var report: Report {
        let types = artifact.flattened()
        let (subset, _) = CodeArtifact.focusedSubset(
            types: types,
            relationships: artifact.relationships,
            configuration: FocusConfiguration(
                rootTypeName: rootType,
                maxDepth: maxDepth,
                direction: .dependents,
                includeInterconnections: false))

        // An unresolvable root yields an empty subset; a resolvable but isolated root yields just
        // itself. Distinguish the two so callers don't read "no dependents" as "type not found".
        guard !subset.isEmpty else {
            return Report(root: rootType, found: false, blastRadius: 0, dependents: [])
        }
        let dependents = subset
            .filter { !$0.matches(name: rootType) }
            .map { Dependent(id: $0.id, qualifiedName: $0.qualifiedName, location: $0.location) }
            .sorted { $0.qualifiedName < $1.qualifiedName }
        return Report(
            root: rootType, found: true, blastRadius: dependents.count, dependents: dependents)
    }
}

private extension TypeDeclaration {
    /// Whether this declaration is the one named by `name` (its id, simple, or qualified name).
    func matches(name: String) -> Bool {
        id == name || self.name == name || qualifiedName == name
    }
}
