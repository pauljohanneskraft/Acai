// Generalizable, language-agnostic enrichment passes over a merged `CodeArtifact`.
//
// These run after per-file parsing + merging (see `AnalysisService`) so the emitted
// artifact already carries resolved, deduplicated and inferred relationships. Each pass
// is pure and order-tolerant; `enriched()` chains them in the intended order.

extension CodeArtifact {

    /// Runs the full enrichment pipeline in order.
    ///
    /// `resolver` supplies each type's language classification (primitives/collections) used when
    /// inferring structural edges, resolved *per type* from its stamped `sourceLanguage` — so a polyglot
    /// artifact infers each language's edges with that language's rules rather than one dominant config.
    /// It is injected (never hard-coded) so the engine stays language-agnostic, and it is *required*: the
    /// resolver carries a mandatory default, so there is no empty configuration to fall into. Because the
    /// pipeline is idempotent, a re-run with the same resolver stays a no-op.
    public func enriched(using resolver: LanguageConfigurationResolver) -> CodeArtifact {
        resolvingExtensions()
            .resolvingRelationshipNames()
            .reclassifyingRelationshipKinds()
            .inferringStructuralEdges(using: resolver)
            .deduplicatingRelationships()
    }

    /// Single-language convenience: enriches every type under one `configuration`. Correct for a
    /// single-language artifact (a parser's own config, a test fixture); polyglot callers use
    /// `enriched(using:)` with a real per-type resolver instead.
    public func enriched(configuration: LanguageConfiguration) -> CodeArtifact {
        enriched(using: LanguageConfigurationResolver(single: configuration))
    }

    // MARK: - Relationship name → id resolution (BUG-12 / GAP-7)

    /// Rewrites relationship `source`/`target` and `inheritedTypes` names from raw names to
    /// canonical type ids, recursing into `nestedTypes` so edges and supertype references to
    /// nested types resolve. Running this in the language-agnostic pipeline means every
    /// language (not just the tree-sitter extractors that opt in) gets consistent qualified
    /// inherited-type names in inspector/detail views.
    public func resolvingRelationshipNames() -> CodeArtifact {
        let resolver = TypeIdentityResolver(types: types)
        var copy = self
        var diagnostics: [ParseDiagnostic] = []

        copy.relationships = relationships.map { rel in
            var resolved = rel
            let source = resolver.resolve(rel.source)
            let target = resolver.resolve(rel.target)
            resolved.source = source.canonicalName
            resolved.target = target.canonicalName
            // Surface only the silent-drop case the issue calls out: a simple name shared by several
            // declared types, left unresolved so it becomes a phantom external node. Genuinely
            // external references (`.external`) are the normal case and are not flagged.
            for (endpoint, kind) in [(source, "source"), (target, "target")] {
                if case .ambiguous(let name) = endpoint {
                    diagnostics.append(ParseDiagnostic(
                        location: SourceLocation(filePath: rel.origin ?? "", line: 0, column: 0),
                        kind: .unresolvedReference,
                        message: "Ambiguous type reference '\(name)' (\(kind) of a \(rel.kind.rawValue) "
                            + "relationship): several declared types share this simple name, so the edge "
                            + "was left unresolved. Qualify the name to disambiguate."))
                }
            }
            return resolved
        }
        copy.types = Self.resolvingInheritedTypeNames(types, using: resolver)
        copy.metadata.parseDiagnostics.append(contentsOf: diagnostics)
        return copy
    }

    /// Rewrites each type's `inheritedTypes[].name` to its canonical id where known, recursing
    /// into `nestedTypes`. Names with no mapping (external supertypes) are left untouched.
    private static func resolvingInheritedTypeNames(
        _ types: [TypeDeclaration], using resolver: TypeIdentityResolver
    ) -> [TypeDeclaration] {
        types.map { type in
            var copy = type
            copy.inheritedTypes = type.inheritedTypes.map { ref in
                var resolved = ref
                resolved.name = resolver.canonicalName(for: ref.name)
                return resolved
            }
            copy.nestedTypes = resolvingInheritedTypeNames(type.nestedTypes, using: resolver)
            return copy
        }
    }

    // MARK: - Inheritance vs conformance (BUG-3, in-codebase only)

    /// Reclassifies an `.inheritance` edge to `.conformance` when its target resolves
    /// to a `protocol`/`interface` declared in this codebase. External first-parents are
    /// left as-is.
    public func reclassifyingRelationshipKinds() -> CodeArtifact {
        let protocolIds = Set(
            Self.allTypes(types)
                .filter { $0.kind == .protocol || $0.kind == .interface }
                .map(\.id))
        guard !protocolIds.isEmpty else { return self }
        var copy = self
        copy.relationships = relationships.map { rel in
            guard rel.kind == .inheritance, protocolIds.contains(rel.target) else { return rel }
            var resolved = rel
            resolved.kind = .conformance
            return resolved
        }
        return copy
    }

    // MARK: - Inferred structural edges (GAP-8 / GAP-9)

    /// Adds composition/aggregation edges from property types, dependency edges from
    /// method/initializer signatures, and a dependency edge for `typealias` targets.
    /// `resolver` classifies primitive/collection type names *per type* from its own language, so a
    /// polyglot artifact doesn't misclassify one language's collections under another's rules.
    public func inferringStructuralEdges(using resolver: LanguageConfigurationResolver) -> CodeArtifact {
        let identity = TypeIdentityResolver(types: types)

        var edges: [Relationship] = []
        for type in Self.allTypes(types) {
            let inference = StructuralEdgeInference(
                configuration: resolver.configuration(for: type),
                resolveId: { identity.canonicalName(for: $0) })
            edges.append(contentsOf: inference.edges(for: type))
        }

        var copy = self
        copy.relationships = relationships + edges
        return copy
    }

    // MARK: - Dedup + redundancy removal (BUG-2)

    /// Removes exact-duplicate edges and weaker inferred edges where a stronger explicit
    /// relationship already covers the same pair.
    public func deduplicatingRelationships() -> CodeArtifact {
        var copy = self
        copy.relationships = RelationshipDeduplicator().reduced(relationships)
        return copy
    }

    // MARK: - Flattening (GAP-7)

    /// A flat list of every type incl. nested ones (nested copies have `nestedTypes`
    /// cleared). Ids are already fully qualified, so they remain unique.
    public func flattened() -> [TypeDeclaration] {
        Self.allTypes(types)
    }

    // MARK: - Shared helpers

    static func allTypes(_ types: [TypeDeclaration]) -> [TypeDeclaration] {
        var result: [TypeDeclaration] = []
        for type in types {
            let nested = allTypes(type.nestedTypes)
            var copy = type
            copy.nestedTypes = []
            result.append(copy)
            result.append(contentsOf: nested)
        }
        return result
    }

    /// Recursively finds an extension's target type (incl. nested types like
    /// `extension Outer.Inner`) and merges the extension's members + nested types into
    /// it. Generic args are stripped (`Foo<T>` → `Foo`). Returns the target's id, or
    /// `nil` when the target is external (extension dropped).
    static func mergeExtension(
        _ ext: TypeDeclaration, targetName: String, into types: inout [TypeDeclaration]
    ) -> String? {
        let name = normalizeTypeName(targetName)
        for index in types.indices {
            if types[index].qualifiedName == name
                || types[index].id == name
                || types[index].name == name {
                types[index].members.append(contentsOf: ext.members)
                types[index].nestedTypes.append(contentsOf: ext.nestedTypes)
                // An extension's own conformance (`extension X: SomeProtocol { ... }`) is often
                // where a type picks up a protocol it satisfies — dropping it here would hide the
                // conformance from anything that reads `inheritedTypes` (e.g. protocol-witness
                // dead-code exemption), so it must be merged alongside members/nestedTypes.
                let existingNames = Set(types[index].inheritedTypes.map(\.name))
                types[index].inheritedTypes.append(
                    contentsOf: ext.inheritedTypes.filter { !existingNames.contains($0.name) })
                return types[index].id
            }
            if let found = mergeExtension(ext, targetName: targetName, into: &types[index].nestedTypes) {
                return found
            }
        }
        return nil
    }

    static func normalizeTypeName(_ raw: String) -> String {
        if let lt = raw.firstIndex(of: "<") {
            return String(raw[..<lt]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

}
