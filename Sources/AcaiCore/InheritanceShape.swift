/// The in-codebase inheritance/conformance shape of a set of types: how deep each sits in its
/// hierarchy (DIT) and how many types derive directly from it (NOC).
///
/// Every depth is resolved once, on construction, so measuring a whole artifact walks each chain a
/// single time instead of once per type asking for it.
struct InheritanceShape {
    private let depths: [String: Int]
    private let childCounts: [String: Int]

    /// Only edges whose *both* endpoints are in `types` count: a supertype outside the codebase has no
    /// measurable depth, so an edge to it would claim a chain that cannot be walked.
    init(types: [TypeDeclaration], relationships: [Relationship]) {
        let typeIDs = Set(types.map(\.id))
        var childCounts: [String: Int] = [:]
        var parents: [String: [String]] = [:]
        for edge in relationships
        where (edge.kind == .inheritance || edge.kind == .conformance)
            && typeIDs.contains(edge.source) && typeIDs.contains(edge.target) {
            childCounts[edge.target, default: 0] += 1
            parents[edge.source, default: []].append(edge.target)
        }

        var memo: [String: Int] = [:]
        // A type already on the path is not revisited, so a cyclic `is-a` graph terminates rather
        // than recursing forever.
        func depth(of id: String, visiting: Set<String>) -> Int {
            if let cached = memo[id] { return cached }
            guard let supertypes = parents[id] else { memo[id] = 0; return 0 }
            var deepest = 0
            for supertype in supertypes where !visiting.contains(supertype) {
                deepest = max(deepest, 1 + depth(of: supertype, visiting: visiting.union([id])))
            }
            memo[id] = deepest
            return deepest
        }
        for type in types { _ = depth(of: type.id, visiting: [type.id]) }

        self.childCounts = childCounts
        self.depths = memo
    }

    /// Depth of inheritance tree: the longest in-codebase chain of supertypes above `id`.
    func depth(of id: String) -> Int { depths[id, default: 0] }

    /// Number of children: types deriving directly from `id`.
    func children(of id: String) -> Int { childCounts[id, default: 0] }

    /// `DIT × NOC` — deeply derived *and* widely subclassed marks a fragile hierarchy hub.
    func deepAndWide(of id: String) -> Int { depth(of: id) * children(of: id) }
}
