import UMLCore

/// A type that exists in both revisions but whose declaration changed.
public struct TypeChange: Codable, Equatable, Sendable {
    public var id: String
    public var kindChange: Change<TypeKind>?
    public var accessChange: Change<AccessLevel>?
    /// Member signatures present only in the new revision.
    public var addedMembers: [String]
    /// Member signatures present only in the old revision.
    public var removedMembers: [String]

    public init(
        id: String,
        kindChange: Change<TypeKind>? = nil,
        accessChange: Change<AccessLevel>? = nil,
        addedMembers: [String] = [],
        removedMembers: [String] = []
    ) {
        self.id = id
        self.kindChange = kindChange
        self.accessChange = accessChange
        self.addedMembers = addedMembers
        self.removedMembers = removedMembers
    }
}

/// A relationship present in both revisions (same source/target/kind) with differing labels.
public struct RelationshipChange: Codable, Equatable, Sendable {
    public var before: Relationship
    public var after: Relationship

    public init(before: Relationship, after: Relationship) {
        self.before = before
        self.after = after
    }
}
