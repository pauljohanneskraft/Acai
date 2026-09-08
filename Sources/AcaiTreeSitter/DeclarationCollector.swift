import AcaiCore

// MARK: - DeclarationCollector

/// Owns the state a Tree-sitter extractor accumulates while walking a file — the discovered types,
/// their relationships, top-level members, and the namespace/type-name bookkeeping needed to resolve
/// them — as one collaborator instead of a handful of loose properties on the extractor itself. A
/// language extractor holds one instance and mutates it as it walks; this type knows no grammar, so
/// any language can share it unchanged.
public struct DeclarationCollector {

    public var types: [TypeDeclaration] = []

    public var relationships: [Relationship] = []

    public var freestandingFunctions: [Member] = []

    /// Top-level (module-scope) `let`/`var`/`val` declarations.
    public var globalVariables: [Member] = []

    public var currentNamespace: String?

    /// Collected in one pre-pass before bodies are extracted so call-site resolution sees the
    /// complete set, including forward-declared siblings.
    public var declaredTypeNames: Set<String> = []

    public init() {}

    public func qualifiedName(_ name: String) -> String {
        currentNamespace.map { "\($0).\(name)" } ?? name
    }

    /// Supertype names are taken verbatim from source text (e.g. `Animal`) while type IDs are fully
    /// qualified (e.g. `com.example.Animal`); this maps short names to qualified IDs, in both
    /// `relationships` and each type's `inheritedTypes`.
    public mutating func resolveRelationshipNames() {
        let resolver = TypeIdentityResolver(types: types)

        relationships = relationships.map { relationship in
            var resolved = relationship
            resolved.source = resolver.canonicalName(for: relationship.source)
            resolved.target = resolver.canonicalName(for: relationship.target)
            return resolved
        }

        func resolveInheritedTypes(in types: inout [TypeDeclaration]) {
            for index in types.indices {
                for refIndex in types[index].inheritedTypes.indices {
                    let name = types[index].inheritedTypes[refIndex].name
                    types[index].inheritedTypes[refIndex].name = resolver.canonicalName(for: name)
                }
                resolveInheritedTypes(in: &types[index].nestedTypes)
            }
        }
        resolveInheritedTypes(in: &types)
    }

    public func buildArtifact(language: CodeArtifact.SourceLanguage, fileName: String) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: [fileName]),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }
}
