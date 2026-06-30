// Generalizable, language-agnostic enrichment passes over a merged `CodeArtifact`.
//
// These run after per-file parsing + merging (see `AnalysisService`) so the emitted
// artifact already carries resolved, deduplicated and inferred relationships. Each pass
// is pure and order-tolerant; `enriched()` chains them in the intended order.

extension CodeArtifact {

    /// Runs the full enrichment pipeline in order.
    ///
    /// `configuration` supplies the language's type-name classification (primitives/collections) used
    /// when inferring structural edges. It is injected — never hard-coded here — so the agnostic
    /// engine stays language-agnostic, and it is *required*: there is no real language with an empty
    /// configuration, so there is deliberately no empty default to fall into. Because the pipeline is
    /// idempotent, a re-run must use the *same* configuration as the first run to stay a no-op.
    public func enriched(configuration: LanguageConfiguration) -> CodeArtifact {
        resolvingExtensions()
            .resolvingRelationshipNames()
            .reclassifyingRelationshipKinds()
            .inferringStructuralEdges(configuration: configuration)
            .deduplicatingRelationships()
    }

    // MARK: - Relationship name → id resolution (BUG-12 / GAP-7)

    /// Rewrites relationship `source`/`target` and `inheritedTypes` names from raw names to
    /// canonical type ids, recursing into `nestedTypes` so edges and supertype references to
    /// nested types resolve. Running this in the language-agnostic pipeline means every
    /// language (not just the tree-sitter extractors that opt in) gets consistent qualified
    /// inherited-type names in inspector/detail views.
    public func resolvingRelationshipNames() -> CodeArtifact {
        let map = Self.buildNameToId(types)
        var copy = self
        copy.relationships = relationships.map { rel in
            var resolved = rel
            resolved.source = map[rel.source] ?? rel.source
            resolved.target = map[rel.target] ?? rel.target
            return resolved
        }
        copy.types = Self.resolvingInheritedTypeNames(types, using: map)
        return copy
    }

    /// Rewrites each type's `inheritedTypes[].name` to its canonical id where known, recursing
    /// into `nestedTypes`. Names with no mapping (external supertypes) are left untouched.
    private static func resolvingInheritedTypeNames(
        _ types: [TypeDeclaration], using map: [String: String]
    ) -> [TypeDeclaration] {
        types.map { type in
            var copy = type
            copy.inheritedTypes = type.inheritedTypes.map { ref in
                var resolved = ref
                resolved.name = map[ref.name] ?? ref.name
                return resolved
            }
            copy.nestedTypes = resolvingInheritedTypeNames(type.nestedTypes, using: map)
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
    /// `configuration` classifies primitive/collection type names (injected, language-supplied).
    public func inferringStructuralEdges(configuration: LanguageConfiguration) -> CodeArtifact {
        let map = Self.buildNameToId(types)
        let resolveId: (String) -> String = { map[$0] ?? $0 }

        var edges: [Relationship] = []
        for type in Self.allTypes(types) {
            edges.append(contentsOf: Self.propertyEdges(for: type, resolveId: resolveId, configuration: configuration))
            edges.append(contentsOf: Self.methodEdges(for: type, resolveId: resolveId, configuration: configuration))
            edges.append(contentsOf: Self.typeAliasEdges(for: type, resolveId: resolveId, configuration: configuration))
        }

        var copy = self
        copy.relationships = relationships + edges
        return copy
    }

    /// Properties/subscripts → composition (scalar) or aggregation (collection).
    private static func propertyEdges(
        for type: TypeDeclaration, resolveId: (String) -> String, configuration: LanguageConfiguration
    ) -> [Relationship] {
        var edges: [Relationship] = []
        for member in type.members where member.kind == .property || member.kind == .subscript {
            guard let typeRef = member.type else { continue }
            for refName in extractReferencedTypeNames(from: typeRef, configuration: configuration) {
                let targetId = resolveId(refName)
                guard targetId != type.id else { continue }
                let isCollection = typeRef.isArray || configuration.isCollectionType(typeRef.name)
                let multiplicity: String = isCollection ? "*" : (typeRef.isOptional ? "0..1" : "1")
                edges.append(Relationship(
                    kind: isCollection ? .aggregation : .composition,
                    source: type.id, target: targetId,
                    targetLabel: multiplicity, label: member.name,
                    origin: member.location?.filePath))
            }
        }
        return edges
    }

    /// Method/initializer parameter & return types → dependency (deduped per type).
    private static func methodEdges(
        for type: TypeDeclaration, resolveId: (String) -> String, configuration: LanguageConfiguration
    ) -> [Relationship] {
        var edges: [Relationship] = []
        var seen = Set<String>()
        for member in type.members where member.kind == .method || member.kind == .initializer {
            let refs = ([member.type].compactMap { $0 }) + member.parameters.compactMap(\.type)
            for ref in refs {
                for refName in extractReferencedTypeNames(from: ref, configuration: configuration) {
                    let targetId = resolveId(refName)
                    guard targetId != type.id, seen.insert(targetId).inserted else { continue }
                    edges.append(Relationship(
                        kind: .dependency, source: type.id, target: targetId,
                        origin: member.location?.filePath))
                }
            }
        }
        return edges
    }

    /// `typealias` → dependency on its underlying type.
    private static func typeAliasEdges(
        for type: TypeDeclaration, resolveId: (String) -> String, configuration: LanguageConfiguration
    ) -> [Relationship] {
        guard type.kind == .typeAlias else { return [] }
        var edges: [Relationship] = []
        for ref in type.inheritedTypes {
            for refName in extractReferencedTypeNames(from: ref, configuration: configuration) {
                let targetId = resolveId(refName)
                guard targetId != type.id else { continue }
                edges.append(Relationship(
                    kind: .dependency, source: type.id, target: targetId,
                    origin: type.location?.filePath))
            }
        }
        return edges
    }

    // MARK: - Dedup + redundancy removal (BUG-2)

    /// Removes exact-duplicate edges and weaker inferred edges where a stronger explicit
    /// relationship already covers the same pair.
    public func deduplicatingRelationships() -> CodeArtifact {
        var copy = self
        copy.relationships = Self.deduplicate(Self.removeRedundantEdges(relationships))
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

    static func buildNameToId(_ types: [TypeDeclaration]) -> [String: String] {
        var map: [String: String] = [:]
        var simpleNameCount: [String: Int] = [:]

        func index(_ types: [TypeDeclaration]) {
            for type in types {
                // Only *exact* keys (id + qualified name) are mapped unconditionally. A bare simple
                // name is mapped separately below and *only when globally unambiguous* — mapping it
                // here would let an ambiguous nested name (e.g. several `Kind` enums) resolve to
                // whichever type was indexed last, fabricating spurious cross-type/-module edges.
                // A top-level type still resolves by its simple name because its `qualifiedName`
                // equals that name (so it also wins over a colliding nested type — natural precedence).
                map[type.id] = type.id
                map[type.qualifiedName] = type.id
                let simple = type.name.components(separatedBy: ".").last ?? type.name
                simpleNameCount[simple, default: 0] += 1
                index(type.nestedTypes)
            }
        }
        index(types)

        func indexSimple(_ types: [TypeDeclaration]) {
            for type in types {
                let simple = type.name.components(separatedBy: ".").last ?? type.name
                // Map simple names only when unambiguous, and never overwrite an exact match.
                if simpleNameCount[simple] == 1, map[simple] == nil {
                    map[simple] = type.id
                }
                indexSimple(type.nestedTypes)
            }
        }
        indexSimple(types)
        return map
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

    private static func deduplicate(_ relationships: [Relationship]) -> [Relationship] {
        var seen = Set<String>()
        return relationships.filter { rel in
            seen.insert("\(rel.source)→\(rel.target):\(rel.kind.rawValue)").inserted
        }
    }

    /// Drops weaker inferred edges when a stronger relationship already covers the pair.
    /// Priority: inheritance/conformance/extension > composition/aggregation > dependency.
    private static func removeRedundantEdges(_ relationships: [Relationship]) -> [Relationship] {
        var strongPairs = Set<String>()
        var mediumPairs = Set<String>()
        for rel in relationships {
            let key = "\(rel.source)→\(rel.target)"
            switch rel.kind {
            case .inheritance, .conformance, .extension:
                strongPairs.insert(key)
            case .composition, .aggregation:
                mediumPairs.insert(key)
            default:
                break
            }
        }
        return relationships.filter { rel in
            let key = "\(rel.source)→\(rel.target)"
            switch rel.kind {
            case .composition, .aggregation:
                return !strongPairs.contains(key)
            case .dependency:
                return !strongPairs.contains(key) && !mediumPairs.contains(key)
            default:
                return true
            }
        }
    }

    // MARK: - Type-name classification

    /// Type names referenced by a `TypeReference` (incl. generic args), excluding names the
    /// language's `configuration` classifies as primitives or collection containers.
    static func extractReferencedTypeNames(
        from ref: TypeReference, configuration: LanguageConfiguration
    ) -> [String] {
        var names: [String] = []
        if !configuration.isPrimitive(ref.name) && !configuration.isCollectionType(ref.name) {
            names.append(ref.name)
        }
        for arg in ref.genericArguments {
            names.append(contentsOf: extractReferencedTypeNames(from: arg, configuration: configuration))
        }
        return names
    }
}
