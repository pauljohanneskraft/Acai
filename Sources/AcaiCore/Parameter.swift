public struct Parameter: Codable, Equatable, Hashable, Sendable {
    public var externalName: String?
    public var internalName: String
    public var type: TypeReference?
    public var defaultValue: String?
    public var isVariadic: Bool
    public var modifiers: [Modifier]

    public init(
        externalName: String? = nil,
        internalName: String,
        type: TypeReference? = nil,
        defaultValue: String? = nil,
        isVariadic: Bool = false,
        modifiers: [Modifier] = []
    ) {
        self.externalName = externalName
        self.internalName = internalName
        self.type = type
        self.defaultValue = defaultValue
        self.isVariadic = isVariadic
        self.modifiers = modifiers
    }
}
