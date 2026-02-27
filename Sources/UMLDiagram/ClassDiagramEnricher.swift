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
        // 1. Flatten nested types, giving them proper display names and unique IDs.
        let flatTypes = flattenTypes(artifact.types)

        // 2. Build name → ID resolution map.
        let resolver = TypeResolver(types: flatTypes)

        // 3. Resolve existing relationships.
        var relationships = artifact.relationships.map { resolver.resolve($0) }

        // 4. Infer composition / aggregation from property types.
        if options.inferCompositionFromProperties {
            relationships.append(contentsOf: inferPropertyRelationships(flatTypes, resolver: resolver))
        }

        // 5. Infer dependency from method parameter/return types.
        if options.inferDependencyFromMethods {
            relationships.append(contentsOf: inferMethodDependencies(flatTypes, resolver: resolver))
        }

        // 6. Remove redundant inferred edges where a stronger relationship exists
        //    (e.g. don't show dependency A→B if inheritance A→B already exists).
        relationships = removeRedundantEdges(relationships)

        // 7. Deduplicate.
        relationships = deduplicate(relationships)

        // 8. Handle external types.
        //
        // Parser-produced edge kinds (inheritance, conformance, extension, nesting,
        // association) are ALWAYS preserved — removing them would be a regression
        // from the pre-enrichment behaviour where DOT rendered every edge.
        //
        // Inferred edge kinds (composition, aggregation, dependency) to external
        // targets are only kept when `showExternalTypes` is enabled.
        let knownIds = Set(flatTypes.map(\.id))

        let inferredKinds: Set<Relationship.Kind> = [.composition, .aggregation, .dependency]

        if !options.showExternalTypes {
            relationships = relationships.filter { rel in
                // Always keep edges where both endpoints are known.
                if knownIds.contains(rel.source) && knownIds.contains(rel.target) { return true }
                // Always keep parser-produced edge kinds even to external targets.
                return !inferredKinds.contains(rel.kind)
            }
        }

        // Create placeholder nodes for every external target still referenced.
        let externalTypes = identifyExternalTypes(
            relationships: relationships, knownIds: knownIds)

        // 9. Build directory groups.
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

    // MARK: - Infer Property Relationships

    private static func inferPropertyRelationships(
        _ types: [TypeDeclaration],
        resolver: TypeResolver
    ) -> [Relationship] {
        var result: [Relationship] = []

        for type in types {
            for member in type.members where member.kind == .property || member.kind == .subscript {
                guard let typeRef = member.type else { continue }
                let refNames = extractReferencedTypeNames(from: typeRef)

                for refName in refNames {
                    guard !isPrimitive(refName) else { continue }
                    let targetId = resolver.resolveId(refName)
                    guard targetId != type.id else { continue } // skip self-references

                    let isCollection = typeRef.isArray || isCollectionType(typeRef.name)
                    let kind: Relationship.Kind = isCollection ? .aggregation : .composition

                    result.append(Relationship(
                        kind: kind,
                        source: type.id,
                        target: targetId,
                        targetLabel: isCollection ? "*" : "1",
                        label: member.name
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Infer Method Dependencies

    private static func inferMethodDependencies(
        _ types: [TypeDeclaration],
        resolver: TypeResolver
    ) -> [Relationship] {
        var result: [Relationship] = []

        for type in types {
            // Avoid duplicate dependency edges from the same source type.
            var seen = Set<String>()

            for member in type.members where member.kind == .method || member.kind == .initializer {
                // Return type.
                if let returnType = member.type {
                    for refName in extractReferencedTypeNames(from: returnType) {
                        guard !isPrimitive(refName) else { continue }
                        let targetId = resolver.resolveId(refName)
                        guard targetId != type.id, seen.insert(targetId).inserted else { continue }
                        result.append(Relationship(
                            kind: .dependency, source: type.id, target: targetId))
                    }
                }

                // Parameter types.
                for param in member.parameters {
                    guard let paramType = param.type else { continue }
                    for refName in extractReferencedTypeNames(from: paramType) {
                        guard !isPrimitive(refName) else { continue }
                        let targetId = resolver.resolveId(refName)
                        guard targetId != type.id, seen.insert(targetId).inserted else { continue }
                        result.append(Relationship(
                            kind: .dependency, source: type.id, target: targetId))
                    }
                }
            }
        }
        return result
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

    // MARK: - Redundancy Removal

    /// Removes weaker inferred edges when a stronger explicit relationship already exists.
    ///
    /// Priority (strongest → weakest):
    /// `inheritance` / `conformance` / `extension` > `composition` / `aggregation` > `dependency`
    private static func removeRedundantEdges(_ relationships: [Relationship]) -> [Relationship] {
        // Build a set of existing strong pairs.
        var strongPairs = Set<String>() // "source→target" for inheritance/conformance/extension
        var mediumPairs = Set<String>() // for composition/aggregation

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
                // Remove if a strong relationship already covers this pair.
                return !strongPairs.contains(key)
            case .dependency:
                // Remove if any stronger relationship covers this pair.
                return !strongPairs.contains(key) && !mediumPairs.contains(key)
            default:
                return true
            }
        }
    }

    // MARK: - Deduplication

    private static func deduplicate(_ relationships: [Relationship]) -> [Relationship] {
        var seen = Set<String>()
        return relationships.filter { rel in
            let key = "\(rel.source)→\(rel.target):\(rel.kind.rawValue)"
            return seen.insert(key).inserted
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

    /// Extracts all non-primitive, non-collection type names from a `TypeReference`,
    /// including types buried in generic arguments.
    private static func extractReferencedTypeNames(from ref: TypeReference) -> [String] {
        var names: [String] = []
        let baseName = ref.name
        if !isPrimitive(baseName) && !isCollectionType(baseName) {
            names.append(baseName)
        }
        for arg in ref.genericArguments {
            names.append(contentsOf: extractReferencedTypeNames(from: arg))
        }
        return names
    }

    /// Returns `true` for built-in / primitive type names that should never produce edges.
    static func isPrimitive(_ name: String) -> Bool {
        primitiveTypes.contains(name)
    }

    /// Returns `true` for well-known collection type names.
    private static func isCollectionType(_ name: String) -> Bool {
        collectionTypes.contains(name)
    }

    // MARK: - Known Type Sets

    private static let primitiveTypes: Set<String> = [
        // Common
        "void", "Void", "Unit", "Nothing", "Never", "Any", "AnyObject", "any",
        "Self", "self", "this",
        // Swift
        "String", "Int", "Double", "Float", "Bool", "Character", "UInt",
        "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64",
        "CGFloat", "Data", "Date", "URL", "UUID", "Error", "Sendable", "Codable",
        "Equatable", "Hashable", "Comparable", "Identifiable", "CustomStringConvertible",
        // Java / Kotlin
        "int", "long", "short", "byte", "float", "double", "boolean", "char",
        "Integer", "Long", "Short", "Byte", "Float", "Double", "Boolean", "Character",
        "Object", "Number", "Comparable", "Serializable", "Cloneable",
        // JS / TS
        "string", "number", "boolean", "undefined", "null", "symbol", "bigint",
        "unknown", "never", "object", "Promise", "Function",
        // Dart
        "dynamic", "num", "var", "inferred",
        // Optional wrappers
        "Optional"
    ]

    private static let collectionTypes: Set<String> = [
        "List", "ArrayList", "LinkedList", "Vector", "Stack", "Queue", "Deque",
        "ArrayDeque", "PriorityQueue",
        "Set", "HashSet", "TreeSet", "LinkedHashSet", "MutableSet",
        "Map", "HashMap", "TreeMap", "LinkedHashMap", "MutableMap",
        "Array", "MutableList", "Iterable", "Collection", "Sequence",
        "Dictionary"
    ]
}
