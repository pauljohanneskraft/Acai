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

    // MARK: - Deferred call-site receiver resolution (cross-file + multi-hop)

    /// Resolves deferred call-site receivers — `.unresolvedTypeName` (a capitalised receiver not
    /// declared in its own file, possibly declared elsewhere in the project) and `.propertyChain` (a
    /// multi-hop property access, e.g. `model.diagrams.add()`, whose middle hop wasn't resolvable
    /// in-file) — against the *fully-merged* project type graph, promoting either to `.type` when it
    /// resolves unambiguously.
    ///
    /// Unlike the rest of `enriched(using:)` (which runs per-language-group inside
    /// `AnalysisService.enrichPerLanguage`, before the final cross-spec merge), this pass needs to see
    /// *every* file project-wide, so `AnalysisService.analyzeProject` calls it once at the very end,
    /// after all specs are merged — additive, not a restructuring of the existing per-language passes.
    /// Idempotent: re-running over an already-resolved artifact changes nothing, since no new
    /// information appears the second time.
    public func resolvingCallSiteReceivers() -> CodeArtifact {
        let flat = Self.allTypes(types)
        let resolver = CallSiteReceiverResolver(
            identity: TypeIdentityResolver(types: types),
            typesByID: Dictionary(flat.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        )

        func resolvingCallSites(_ sites: [CallSite], owningTypeID: String?) -> [CallSite] {
            sites.map { site in
                var copy = site
                copy.receiver = resolver.resolved(site.receiver, owningTypeID: owningTypeID)
                return copy
            }
        }
        func resolvingMembers(_ members: [Member], owningTypeID: String?) -> [Member] {
            members.map { member in
                var copy = member
                copy.callSites = resolvingCallSites(member.callSites, owningTypeID: owningTypeID)
                return copy
            }
        }
        func resolvingTypes(_ types: [TypeDeclaration]) -> [TypeDeclaration] {
            types.map { type in
                var copy = type
                copy.members = resolvingMembers(type.members, owningTypeID: type.id)
                copy.nestedTypes = resolvingTypes(type.nestedTypes)
                return copy
            }
        }

        var copy = self
        copy.types = resolvingTypes(types)
        // No enclosing type for a freestanding function, so `.ownProperty` (which resolves against
        // the call site's *own* type) can never apply here — matches `CallSiteCollector` only ever
        // producing that case when it has an enclosing type name to defer against.
        copy.freestandingFunctions = resolvingMembers(freestandingFunctions, owningTypeID: nil)
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

    /// Finds an extension's target type (incl. nested types like `extension Outer.Inner`) anywhere
    /// in `types` and merges the extension's members + nested types into it. Generic args are
    /// stripped (`Foo<T>` → `Foo`). Returns the target's id, or `nil` when the target is external
    /// (extension dropped).
    static func mergeExtension(
        _ ext: TypeDeclaration, targetName: String, into types: inout [TypeDeclaration]
    ) -> String? {
        let name = normalizeTypeName(targetName)
        guard let targetId = extensionTargetID(ext, name: name, in: types) else { return nil }
        mergeExtensionMembers(ext, intoTypeWithID: targetId, into: &types)
        return targetId
    }

    /// Resolves the id of the single type `name` should merge into.
    ///
    /// An exact `qualifiedName`/`id` match is unambiguous by construction (this project's id scheme
    /// carries no module prefix, so a collision there would mean two identically-named *top-level*
    /// types — a separate, unaddressed edge case, not the one this resolves) and wins outright.
    /// Otherwise falls back to a bare simple-name match, scoped to the extension's own module (via
    /// ``ModuleResolver``): a bare name shared with an unrelated type in another module — e.g. an
    /// extension of an *external* type (`extension Node` on `SwiftTreeSitter.Node`) that happens to
    /// share a name with an unrelated in-project nested type (`FreeformDiagram.Node`) — must not
    /// silently merge into it, so the fallback only accepts the match when it is the *sole*
    /// same-module candidate.
    private static func extensionTargetID(
        _ ext: TypeDeclaration, name: String, in types: [TypeDeclaration]
    ) -> String? {
        let flat = allTypes(types)
        if let exact = flat.first(where: { $0.qualifiedName == name || $0.id == name }) {
            return exact.id
        }
        let extModule = ModuleResolver.standard.productName(forFilePath: ext.location?.filePath ?? "")
        let sameModuleMatches = flat.filter {
            $0.name == name
                && ModuleResolver.standard.productName(forFilePath: $0.location?.filePath ?? "") == extModule
        }
        guard sameModuleMatches.count == 1 else { return nil }
        return sameModuleMatches[0].id
    }

    /// Merges `ext`'s members/nested types/inherited types into the (possibly nested) type with
    /// `id`, recursing into `nestedTypes` to find it.
    private static func mergeExtensionMembers(
        _ ext: TypeDeclaration, intoTypeWithID id: String, into types: inout [TypeDeclaration]
    ) {
        for index in types.indices {
            if types[index].id == id {
                types[index].members.append(contentsOf: ext.members)
                types[index].nestedTypes.append(contentsOf: ext.nestedTypes)
                // An extension's own conformance (`extension X: SomeProtocol { ... }`) is often
                // where a type picks up a protocol it satisfies — dropping it here would hide the
                // conformance from anything that reads `inheritedTypes` (e.g. protocol-witness
                // dead-code exemption), so it must be merged alongside members/nestedTypes.
                let existingNames = Set(types[index].inheritedTypes.map(\.name))
                types[index].inheritedTypes.append(
                    contentsOf: ext.inheritedTypes.filter { !existingNames.contains($0.name) })
                return
            }
            mergeExtensionMembers(ext, intoTypeWithID: id, into: &types[index].nestedTypes)
        }
    }

    static func normalizeTypeName(_ raw: String) -> String {
        if let lt = raw.firstIndex(of: "<") {
            return String(raw[..<lt]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

}

/// Resolves a call site's deferred receiver (`.unresolvedTypeName`/`.propertyChain`) against the
/// fully-merged project type graph — the whole-project context neither is provable at parse time.
/// A value you instantiate once per `resolvingCallSiteReceivers()` call and ask to resolve each site.
private struct CallSiteReceiverResolver {
    let identity: TypeIdentityResolver
    let typesByID: [String: TypeDeclaration]

    /// The receiver unchanged, or promoted to `.type` when a deferred case now resolves
    /// unambiguously against the full project; never guesses across an ambiguous or absent match.
    /// `owningTypeID` is the fully-merged type the call site's own member belongs to — needed only
    /// to resolve `.ownProperty`, which looks a property up on that exact type (`nil` for a
    /// freestanding function, which has no enclosing type to check).
    func resolved(_ receiver: CallReceiver, owningTypeID: String?) -> CallReceiver {
        switch receiver {
        case .unresolvedTypeName(let name):
            guard case .resolved = identity.resolve(name) else { return receiver }
            return .type(name)
        case .propertyChain(let headTypeName, let hops):
            guard let finalTypeName = walkChain(headTypeName: headTypeName, hops: hops) else { return receiver }
            return .type(finalTypeName)
        case .ownProperty(let propertyName, let remainingHops):
            guard let owningTypeID, let owningType = typesByID[owningTypeID],
                  let property = owningType.members.first(where: { $0.kind == .property && $0.name == propertyName }),
                  let propertyType = property.type?.name,
                  let finalTypeName = walkChain(headTypeName: propertyType, hops: remainingHops)
            else { return receiver }
            return .type(finalTypeName)
        case .selfDispatch, .type, .free, .unknown:
            return receiver
        }
    }

    /// Walks `hops` from `headTypeName`'s declared properties, one hop at a time, resolving each
    /// hop's declared property type through the full project type graph. Returns the final hop's
    /// type name only when every hop — including the last — resolves to a single, unambiguous,
    /// declared type; drops (returns `nil`) at the first unknown/ambiguous hop rather than guessing.
    private func walkChain(headTypeName: String, hops: [String]) -> String? {
        var currentTypeName = headTypeName
        for hop in hops {
            guard case .resolved(let id) = identity.resolve(currentTypeName),
                  let currentType = typesByID[id.value],
                  let property = currentType.members.first(where: { $0.kind == .property && $0.name == hop }),
                  let nextTypeName = property.type?.name
            else { return nil }
            currentTypeName = nextTypeName
        }
        guard case .resolved = identity.resolve(currentTypeName) else { return nil }
        return currentTypeName
    }
}
