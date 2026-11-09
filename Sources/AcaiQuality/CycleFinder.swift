import AcaiCore

/// Finds dependency cycles in a `CodeArtifact`, at module or type scope. Module adjacency is
/// provenance-aware (via `ModuleAttribution`), so a cross-module extension does not manufacture a
/// phantom upward edge / false cycle.
///
/// Shared by `QualityEvaluator` (the `cycle` rule) and the `quality --explore` cycle listing so the
/// two never disagree.
public struct CycleFinder: Sendable {
    public enum Scope: String, Sendable, CaseIterable {
        case modules
        case types
    }

    /// A strongly-connected component's members, sorted for determinism.
    public struct Cycle: Sendable, Equatable {
        /// One hop of a module cycle, with the type reference that creates it — the evidence needed
        /// to break the hop or to disprove it, which the member names alone don't carry.
        public struct Witness: Sendable, Equatable {
            /// The module the hop leaves, and the one it enters.
            public var from: String
            public var to: String
            /// The referencing type and the type it references.
            public var sourceType: String
            public var targetType: String
            public var kind: Relationship.Kind
            /// `sourceType`'s declaration site.
            public var location: SourceLocation?
            /// The file the reference is written in, when provenance puts it outside `sourceType`'s
            /// own file — a cross-module extension references from its own module, which is what
            /// decided this hop's `from`.
            public var referenceFile: String?

            public var description: String {
                let site = location.map { " at \($0.filePath):\($0.line)" } ?? ""
                let reference = referenceFile.map { " (reference in \($0))" } ?? ""
                return "\(from) → \(to) via \(sourceType) → \(targetType) (\(kind.rawValue))\(site)\(reference)"
            }

            /// Total order, so a cycle's witnesses and the choice of witness per hop are both
            /// deterministic: hop endpoints first, then the referencing edge.
            func precedes(_ other: Witness) -> Bool {
                if from != other.from { return from < other.from }
                if to != other.to { return to < other.to }
                return edgeKey.lexicographicallyPrecedes(other.edgeKey)
            }

            private var edgeKey: [String] {
                [sourceType, targetType, kind.rawValue, location?.filePath ?? "", String(location?.line ?? 0)]
            }
        }

        public var scope: Scope
        public var members: [String]
        /// One witnessing edge per hop between members, for a `.modules` cycle. Empty at `.types`
        /// scope, where the members *are* the referencing types.
        public var witnesses: [Witness]

        public init(scope: Scope, members: [String], witnesses: [Witness] = []) {
            self.scope = scope
            self.members = members
            self.witnesses = witnesses
        }

        /// `A → B → C → A`-style rendering of the cycle.
        public var description: String {
            (members + [members.first].compactMap { $0 }).joined(separator: " → ")
        }

        /// The witnesses as one line, or `nil` when the cycle carries none.
        public var evidence: String? {
            guard !witnesses.isEmpty else { return nil }
            return witnesses.map(\.description).joined(separator: "; ")
        }

        /// The cycle as commented YAML: the hop list a generated rules file records as known debt.
        public var knownDebtLines: [String] {
            ["#   known debt: \(description)"] + witnesses.map { "#     \($0.description)" }
        }
    }

    private let graph: GraphView
    private let attribution: ModuleAttribution

    public init(graph: GraphView) {
        self.graph = graph
        let idToModule = Dictionary(graph.nodes.map { ($0.id, $0.module) }, uniquingKeysWith: { first, _ in first })
        self.attribution = ModuleAttribution(modules: graph.modules, idToModule: idToModule)
    }

    public init(
        artifact: CodeArtifact,
        moduleResolver: ModuleResolver = .standard,
        languageResolver: LanguageConfigurationResolver
    ) {
        self.init(
            graph: GraphView(
                artifact: artifact, moduleResolver: moduleResolver, languageResolver: languageResolver))
    }

    public func cycles(scope: Scope) -> [Cycle] {
        switch scope {
        case .modules:
            let hops = moduleHops
            return components(adjacency: hops.adjacency, scope: .modules).map { cycle in
                Cycle(scope: .modules, members: cycle.members, witnesses: hops.witnesses(within: cycle.members))
            }
        case .types:
            return components(adjacency: typeAdjacency, scope: .types)
        }
    }

    /// The `cycle` rule's breaches — one per cycle, carrying its witness edges so a reported cycle
    /// can be acted on. Shared by the rule, `quality --explore` and the MCP tool so the three agree.
    public func violations(scope: Scope) -> [Violation] {
        let label = scope == .modules ? "Module" : "Type"
        return cycles(scope: scope).map { cycle in
            var detail = ["scope": scope.rawValue]
            var message = "\(label) dependency cycle: \(cycle.description)."
            if let evidence = cycle.evidence {
                detail["witnesses"] = evidence
                message += " Via: \(evidence)."
            }
            return Violation(
                ruleKind: "cycle",
                message: message,
                subject: cycle.members.joined(separator: ","),
                // A type cycle can point at the first member's declaration; a module cycle has no
                // single site, so its witnesses carry the locations instead.
                source: scope == .types ? cycle.members.first.flatMap { graph.node(id: $0)?.location } : nil,
                detail: detail
            )
        }
    }

    private var typeAdjacency: [String: Set<String>] {
        var adjacency: [String: Set<String>] = [:]
        for edge in graph.relationships {
            guard graph.node(id: edge.source) != nil, graph.node(id: edge.target) != nil,
                  edge.source != edge.target else { continue }
            adjacency[edge.source, default: []].insert(edge.target)
        }
        return adjacency
    }

    private var moduleHops: ModuleHopIndex {
        var index = ModuleHopIndex()
        for edge in graph.relationships {
            guard let sourceModule = attribution.sourceModule(of: edge),
                  let targetModule = attribution.targetModule(of: edge),
                  sourceModule != targetModule else { continue }
            let location = graph.node(id: edge.source)?.location
            index.insert(Cycle.Witness(
                from: sourceModule,
                to: targetModule,
                sourceType: edge.source,
                targetType: edge.target,
                kind: edge.kind,
                location: location,
                referenceFile: edge.origin == location?.filePath ? nil : edge.origin))
        }
        return index
    }

    private func components(adjacency: [String: Set<String>], scope: Scope) -> [Cycle] {
        StronglyConnectedComponents(adjacency: adjacency).cycles
            .map { Cycle(scope: scope, members: $0.sorted()) }
            .sorted { $0.members.lexicographicallyPrecedes($1.members) }
    }
}

/// The module graph as it is built: adjacency for the cycle search, plus the edge chosen to witness
/// each module hop (the first in `Witness.precedes` order, so the choice is stable).
private struct ModuleHopIndex {
    private struct Hop: Hashable {
        let from: String
        let to: String
    }

    private(set) var adjacency: [String: Set<String>] = [:]
    private var witnessByHop: [Hop: CycleFinder.Cycle.Witness] = [:]

    mutating func insert(_ witness: CycleFinder.Cycle.Witness) {
        adjacency[witness.from, default: []].insert(witness.to)
        let hop = Hop(from: witness.from, to: witness.to)
        guard let incumbent = witnessByHop[hop] else {
            witnessByHop[hop] = witness
            return
        }
        if witness.precedes(incumbent) { witnessByHop[hop] = witness }
    }

    /// Every hop running between the given members, in witness order.
    func witnesses(within members: [String]) -> [CycleFinder.Cycle.Witness] {
        let members = Set(members)
        return witnessByHop.values
            .filter { members.contains($0.from) && members.contains($0.to) }
            .sorted { $0.precedes($1) }
    }
}
