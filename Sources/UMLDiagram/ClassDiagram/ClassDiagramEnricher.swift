import UMLCore

/// Options controlling how a `CodeArtifact` is enriched for class-diagram rendering.
public struct EnrichmentOptions: Sendable {
    /// When `true`, properties whose declared type matches a known type produce
    /// composition/aggregation edges (collection properties → aggregation, scalar → composition).
    public var inferCompositionFromProperties: Bool

    /// When `true`, method parameter and return types that match known types produce
    /// dependency edges.
    public var inferDependencyFromMethods: Bool

    /// When `true`, types referenced in relationships but not defined in the artifact
    /// are included as lightweight "external" placeholder nodes rendered in gray.
    public var showExternalTypes: Bool

    public init(
        inferCompositionFromProperties: Bool = true,
        inferDependencyFromMethods: Bool = true,
        showExternalTypes: Bool = false
    ) {
        self.inferCompositionFromProperties = inferCompositionFromProperties
        self.inferDependencyFromMethods = inferDependencyFromMethods
        self.showExternalTypes = showExternalTypes
    }
}

/// Post-processes a `CodeArtifact` to produce a richer model for class-diagram rendering.
///
/// Responsibilities:
/// - Flattens nested types, giving them display names that include nesting context
///   (e.g. `Outer.Inner`) while keeping fully-qualified IDs for unique identification.
/// - Resolves relationship source/target strings to match actual type IDs so edges
///   connect correctly even when parsers used short names.
/// - Infers composition / aggregation edges from property types.
/// - Infers dependency edges from method parameter/return types.
/// - Identifies external types (referenced but not defined in the codebase).
public enum ClassDiagramEnricher {

    /// The enriched result ready for DOT rendering.
    public struct Result: Sendable {
        /// All types (including flattened nested types).
        public var types: [TypeDeclaration]
        /// Resolved and enriched relationships.
        public var relationships: [Relationship]
        /// Types referenced but not defined in the codebase (external dependencies).
        public var externalTypes: [TypeDeclaration]
        /// Maps each directory path to the type IDs it contains, for grouping.
        public var directoryGroups: [String: [String]]
    }

    public static func enrich(
        _ artifact: CodeArtifact,
        options: EnrichmentOptions = .init()
    ) -> Result {
        // All structural enrichment (extension resolution, name→id resolution,
        // inheritance/conformance reclassification, inferred composition/aggregation/
        // dependency edges, dedup) is owned by UMLCore and runs exactly once here.
        // It is idempotent, so an already-enriched artifact (e.g. from AnalysisService)
        // is unaffected.
        let base = artifact.enriched()

        // Flatten nested types, giving them display names that include nesting context.
        let flatTypes = flattenTypes(base.types)
        let resolver = TypeResolver(types: flatTypes)
        var relationships = base.relationships.map { resolver.resolve($0) }

        // Honour the inference toggles by filtering the kinds UMLCore inferred.
        if !options.inferCompositionFromProperties {
            relationships.removeAll { $0.kind == .composition || $0.kind == .aggregation }
        }
        if !options.inferDependencyFromMethods {
            relationships.removeAll { $0.kind == .dependency }
        }

        // External types: parser-produced edges (inheritance/conformance/…) are always
        // kept; inferred edges to external targets only when `showExternalTypes` is set.
        let knownIds = Set(flatTypes.map(\.id))
        let inferredKinds: Set<Relationship.Kind> = [.composition, .aggregation, .dependency]
        if !options.showExternalTypes {
            relationships = relationships.filter { rel in
                if knownIds.contains(rel.source) && knownIds.contains(rel.target) { return true }
                return !inferredKinds.contains(rel.kind)
            }
        }

        let externalTypes = identifyExternalTypes(relationships: relationships, knownIds: knownIds)
        let directoryGroups = buildDirectoryGroups(flatTypes)

        return Result(
            types: flatTypes,
            relationships: relationships,
            externalTypes: externalTypes,
            directoryGroups: directoryGroups
        )
    }

    // MARK: - Flatten Nested Types

    private static func flattenTypes(
        _ types: [TypeDeclaration],
        parentDisplayName: String? = nil,
        parentId: String? = nil
    ) -> [TypeDeclaration] {
        var result: [TypeDeclaration] = []
        for var type in types {
            // Update display name for nested types to include parent context.
            if let parent = parentDisplayName {
                type.name = "\(parent).\(type.name)"
            }

            // Ensure the ID includes the parent scope for nested types
            // so it's unique across the codebase.
            if let pid = parentId, !type.id.hasPrefix(pid) {
                type.id = "\(pid).\(type.id.components(separatedBy: ".").last ?? type.id)"
                type.qualifiedName = type.id
            }

            // Recursively flatten nested types.
            let nested = flattenTypes(
                type.nestedTypes,
                parentDisplayName: type.name,
                parentId: type.id
            )
            type.nestedTypes = []

            result.append(type)
            result.append(contentsOf: nested)
        }
        return result
    }

    // MARK: - Type Resolution

    private struct TypeResolver {
        /// Maps various name forms to the canonical type ID.
        let nameToId: [String: String]
        let knownIds: Set<String>

        init(types: [TypeDeclaration]) {
            var map: [String: String] = [:]
            var ids = Set<String>()
            // Track how many types share the same simple name so we can detect ambiguity.
            var simpleNameCount: [String: Int] = [:]

            for type in types {
                ids.insert(type.id)

                // Exact matches: id and qualifiedName always map to their own id.
                map[type.id] = type.id
                map[type.qualifiedName] = type.id

                // Display name (may contain nesting context).
                map[type.name] = type.id

                // Count simple-name occurrences.
                let simpleName = type.name.components(separatedBy: ".").last ?? type.name
                simpleNameCount[simpleName, default: 0] += 1
            }

            // Map simple names only when unambiguous.
            for type in types {
                let simpleName = type.name.components(separatedBy: ".").last ?? type.name
                if simpleNameCount[simpleName] == 1 {
                    map[simpleName] = type.id
                }
                // Even when ambiguous, still allow prefix-based lookup later;
                // for now just add the mapping if it doesn't exist yet.
                if map[simpleName] == nil {
                    map[simpleName] = type.id
                }
            }

            self.nameToId = map
            self.knownIds = ids
        }

        func resolveId(_ name: String) -> String {
            nameToId[name] ?? name
        }

        func resolve(_ relationship: Relationship) -> Relationship {
            var rel = relationship
            rel.source = resolveId(rel.source)
            rel.target = resolveId(rel.target)
            return rel
        }
    }

    // MARK: - External Types

    private static func identifyExternalTypes(
        relationships: [Relationship],
        knownIds: Set<String>
    ) -> [TypeDeclaration] {
        var externalIds = Set<String>()
        for rel in relationships {
            if !knownIds.contains(rel.source) && !isPrimitive(rel.source) {
                externalIds.insert(rel.source)
            }
            if !knownIds.contains(rel.target) && !isPrimitive(rel.target) {
                externalIds.insert(rel.target)
            }
        }

        return externalIds.sorted().map { id in
            let name = id.components(separatedBy: ".").last ?? id
            return TypeDeclaration(
                id: id, name: name, qualifiedName: id, kind: .class
            )
        }
    }

    // MARK: - Directory Groups

    private static func buildDirectoryGroups(_ types: [TypeDeclaration]) -> [String: [String]] {
        var groups: [String: [String]] = [:]
        for type in types {
            guard let filePath = type.location?.filePath else { continue }
            let directory: String
            if let lastSlash = filePath.lastIndex(of: "/") {
                directory = String(filePath[filePath.startIndex..<lastSlash])
            } else {
                directory = ""
            }
            groups[directory, default: []].append(type.id)
        }
        return groups
    }

    // MARK: - Type Reference Helpers

    /// Returns `true` for built-in / primitive type names that should never be shown
    /// as external placeholder nodes. Delegates to the shared UMLCore classification.
    static func isPrimitive(_ name: String) -> Bool {
        CodeArtifact.isPrimitive(name)
    }
}
