/// The declarations a parser accumulates while walking one source file, and the naming discipline
/// that turns them into a `CodeArtifact` satisfying the producer contract on ``CodeParser``.
///
/// In `AcaiCore` rather than `AcaiTreeSitter` because it names no `Node`.
public struct DeclarationBuilder: Sendable {

    public var types: [TypeDeclaration] = []

    public var relationships: [Relationship] = []

    public var freestandingFunctions: [Member] = []

    /// Top-level (module-scope) `let`/`var`/`val` declarations.
    public var globalVariables: [Member] = []

    /// Collected in one pre-pass before bodies are extracted so call-site resolution sees the
    /// complete set, including forward-declared siblings.
    public var declaredTypeNames: Set<String> = []

    public private(set) var currentNamespace: String?

    public init() {}

    // MARK: - Naming

    public func qualifiedName(_ name: String) -> String {
        currentNamespace.map { "\($0).\(name)" } ?? name
    }

    /// Returns the namespace to restore: `let outer = builder.enter(namespace: id)` /
    /// `defer { builder.leave(outer) }`. Save/restore rather than a closure because an extractor is
    /// a `struct` that mutates itself while walking, so a closure that also mutated it would
    /// overlap exclusive access.
    public mutating func enter(namespace: String) -> String? {
        let saved = currentNamespace
        currentNamespace = namespace
        return saved
    }

    public mutating func leave(_ namespace: String?) {
        currentNamespace = namespace
    }

    // MARK: - Relationships

    /// The edges' `target` is each supertype's simple name; ``resolveRelationshipNames()`` later
    /// maps it to a qualified id.
    public mutating func recordSupertypeRelationships(
        from owner: String,
        to supertypes: [TypeReference],
        kind: Relationship.Kind
    ) {
        relationships.append(contentsOf: supertypes.map { $0.relationship(kind: kind, source: owner) })
    }

    /// Supertype names are taken verbatim from source text (e.g. `Animal`) while type IDs are fully
    /// qualified (e.g. `com.example.Animal`); this maps short names to qualified IDs, using the same
    /// resolver and ambiguity rule as the agnostic enrichment pass.
    public mutating func resolveRelationshipNames() {
        let resolver = TypeIdentityResolver(types: types)

        relationships = relationships.map { relationship in
            var resolved = relationship
            resolved.source = resolver.canonicalName(for: relationship.source)
            resolved.target = resolver.canonicalName(for: relationship.target)
            return resolved
        }

        resolveInheritedTypes(in: &types, using: resolver)
    }

    private func resolveInheritedTypes(in types: inout [TypeDeclaration], using resolver: TypeIdentityResolver) {
        for index in types.indices {
            for referenceIndex in types[index].inheritedTypes.indices {
                let name = types[index].inheritedTypes[referenceIndex].name
                types[index].inheritedTypes[referenceIndex].name = resolver.canonicalName(for: name)
            }
            resolveInheritedTypes(in: &types[index].nestedTypes, using: resolver)
        }
    }

    // MARK: - Assembly

    public func artifact(language: CodeArtifact.SourceLanguage, filePath: String) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: [filePath]),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }
}
