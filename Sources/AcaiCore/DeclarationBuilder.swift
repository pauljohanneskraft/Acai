/// The declarations a parser accumulates while walking one source file, plus the namespace and
/// naming discipline that turns them into a `CodeArtifact` satisfying the producer contract.
///
/// This is the half of an extractor that has nothing to do with any grammar: every language keeps
/// the same six pieces of state and qualifies names the same way. Holding them here lets a parser
/// *delegate* to a value it owns rather than inherit them from a protocol it conforms to — the
/// difference being that a small collaborator type can be handed a `DeclarationBuilder` too, where
/// a protocol conformance is reachable only by the one type that is the extractor.
///
/// In `AcaiCore` rather than `AcaiTreeSitter` because it names no `Node`: a SwiftSyntax-based
/// parser keeps the same four arrays and can adopt it unchanged.
public struct DeclarationBuilder: Sendable {

    public var types: [TypeDeclaration] = []

    public var relationships: [Relationship] = []

    public var freestandingFunctions: [Member] = []

    /// Top-level (module-scope) `let`/`var`/`val` declarations.
    public var globalVariables: [Member] = []

    /// Collected in one pre-pass before bodies are extracted so call-site resolution sees the
    /// complete set, including forward-declared siblings.
    public var declaredTypeNames: Set<String> = []

    /// The enclosing package/namespace/type, or `nil` at file scope.
    public private(set) var currentNamespace: String?

    public init() {}

    // MARK: - Naming

    /// A declaration's id and qualified name: the simple name prefixed by the enclosing namespace.
    public func qualifiedName(_ name: String) -> String {
        currentNamespace.map { "\($0).\(name)" } ?? name
    }

    /// Enters `namespace` and returns the namespace to restore, so a caller reads
    /// `let outer = builder.enter(namespace: id)` / `defer { builder.leave(outer) }`.
    ///
    /// Nesting is a save/restore rather than a closure because an extractor is a `struct` that
    /// mutates itself while walking: passing a closure that also mutates it would overlap
    /// exclusive access to the same value.
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
    /// qualified (e.g. `com.example.Animal`); this maps short names to qualified IDs.
    ///
    /// Delegates to ``TypeIdentityResolver`` so per-file resolution uses the same name→id mapping
    /// and ambiguity rule as the agnostic enrichment pass.
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
