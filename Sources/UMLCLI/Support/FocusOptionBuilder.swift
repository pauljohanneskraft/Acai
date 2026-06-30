import UMLCore

/// Builds a `FocusConfiguration` from the shared `--focus*` CLI flags. A value you instantiate with
/// the flags and read `configuration` from; it is `nil` when no root type was given, so the diagram
/// falls back to rendering the whole codebase.
struct FocusOptionBuilder {
    let rootTypeName: String?
    let depth: Int?
    let direction: FocusDirectionOption?
    let relationshipKinds: [RelationshipKindOption]
    let includeInterconnections: Bool

    var configuration: FocusConfiguration? {
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
