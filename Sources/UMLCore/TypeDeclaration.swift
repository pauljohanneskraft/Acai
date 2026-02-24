public struct TypeDeclaration: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var qualifiedName: String
    public var kind: TypeKind
    public var accessLevel: AccessLevel?
    public var modifiers: [Modifier]
    public var genericParameters: [GenericParameter]
    public var inheritedTypes: [TypeReference]
    public var members: [Member]
    public var enumCases: [EnumCase]
    public var nestedTypes: [TypeDeclaration]
    public var annotations: [String]
    public var extensionOf: String?
    public var namespace: String?
    public var location: SourceLocation?

    public init(
        id: String,
        name: String,
        qualifiedName: String,
        kind: TypeKind,
        accessLevel: AccessLevel? = nil,
        modifiers: [Modifier] = [],
        genericParameters: [GenericParameter] = [],
        inheritedTypes: [TypeReference] = [],
        members: [Member] = [],
        enumCases: [EnumCase] = [],
        nestedTypes: [TypeDeclaration] = [],
        annotations: [String] = [],
        extensionOf: String? = nil,
        namespace: String? = nil,
        location: SourceLocation? = nil
    ) {
        self.id = id
        self.name = name
        self.qualifiedName = qualifiedName
        self.kind = kind
        self.accessLevel = accessLevel
        self.modifiers = modifiers
        self.genericParameters = genericParameters
        self.inheritedTypes = inheritedTypes
        self.members = members
        self.enumCases = enumCases
        self.nestedTypes = nestedTypes
        self.annotations = annotations
        self.extensionOf = extensionOf
        self.namespace = namespace
        self.location = location
    }
}
