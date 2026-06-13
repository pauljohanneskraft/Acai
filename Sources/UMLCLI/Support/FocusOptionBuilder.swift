import UMLCore

/// Builds a `FocusConfiguration` from the shared `--focus*` CLI flags. Returns `nil` when
/// no root type was given, so the diagram falls back to rendering the whole codebase.
enum FocusOptionBuilder {
    static func make(
        rootTypeName: String?,
        depth: Int?,
        direction: FocusDirectionOption?,
        relationshipKinds: [RelationshipKindOption],
        includeInterconnections: Bool
    ) -> FocusConfiguration? {
        guard let rootTypeName else { return nil }
        return FocusConfiguration(
            rootTypeName: rootTypeName,
            maxDepth: depth,
            direction: direction?.direction ?? .dependencies,
            includedRelationshipKinds: relationshipKinds.isEmpty
                ? Set(Relationship.Kind.allCases)
                : Set(relationshipKinds.map(\.kind)),
            includeInterconnections: includeInterconnections
        )
    }
}
