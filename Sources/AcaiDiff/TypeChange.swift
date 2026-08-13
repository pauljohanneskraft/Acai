import AcaiCore

/// A type that exists in both revisions but whose declaration changed.
public struct TypeChange: Codable, Equatable, Sendable {
    public var id: String
    public var kindChange: Change<TypeKind>?
    public var accessChange: Change<AccessLevel>?
    /// Member signatures present only in the new revision. Excludes members in `changedMembers`.
    public var addedMembers: [String]
    /// Member signatures present only in the old revision. Excludes members in `changedMembers`.
    public var removedMembers: [String]
    /// Same-named members on both sides whose signature differs, paired rather than reported as
    /// an unrelated add+remove.
    public var changedMembers: [MemberChange]

    public init(
        id: String,
        kindChange: Change<TypeKind>? = nil,
        accessChange: Change<AccessLevel>? = nil,
        addedMembers: [String] = [],
        removedMembers: [String] = [],
        changedMembers: [MemberChange] = []
    ) {
        self.id = id
        self.kindChange = kindChange
        self.accessChange = accessChange
        self.addedMembers = addedMembers
        self.removedMembers = removedMembers
        self.changedMembers = changedMembers
    }
}

/// A member present under the same name in both revisions whose full signature differs.
public struct MemberChange: Codable, Equatable, Sendable {
    public var name: String
    public var before: String
    public var after: String

    public init(name: String, before: String, after: String) {
        self.name = name
        self.before = before
        self.after = after
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
