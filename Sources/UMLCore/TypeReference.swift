public struct TypeReference: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var genericArguments: [TypeReference]
    public var isOptional: Bool
    public var isArray: Bool

    public init(
        name: String,
        genericArguments: [TypeReference] = [],
        isOptional: Bool = false,
        isArray: Bool = false
    ) {
        self.name = name
        self.genericArguments = genericArguments
        self.isOptional = isOptional
        self.isArray = isArray
    }
}
