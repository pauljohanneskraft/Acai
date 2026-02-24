public struct EnumCase: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var rawValue: String?
    public var associatedValues: [Parameter]
    public var location: SourceLocation?

    public init(
        name: String,
        rawValue: String? = nil,
        associatedValues: [Parameter] = [],
        location: SourceLocation? = nil
    ) {
        self.name = name
        self.rawValue = rawValue
        self.associatedValues = associatedValues
        self.location = location
    }
}
