public extension TypeReference {
    /// The ``Relationship`` edge a parser records alongside this reference when it resolves a
    /// superclass/interface/mixin/supertype list into both an `inheritedTypes` entry and a graph
    /// edge — the same pairing every Tree-sitter-based language extractor repeats once per resolved
    /// base type. `target` is this reference's ``name``.
    func relationship(kind: Relationship.Kind, source: String, label: String? = nil) -> Relationship {
        Relationship(kind: kind, source: source, target: name, label: label)
    }
}
