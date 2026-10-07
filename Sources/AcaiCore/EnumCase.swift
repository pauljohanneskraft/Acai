public struct EnumCase: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var rawValue: String?
    public var associatedValues: [Parameter]
    public var location: SourceLocation?
    /// What the author wrote about this case, as prose. `nil` when it carries no documentation.
    public var documentation: String?

    public init(
        name: String,
        rawValue: String? = nil,
        associatedValues: [Parameter] = [],
        location: SourceLocation? = nil,
        documentation: String? = nil
    ) {
        self.name = name
        self.rawValue = rawValue
        self.associatedValues = associatedValues
        self.location = location
        self.documentation = documentation
    }
}
