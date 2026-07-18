public struct GenericParameter: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var constraints: [GenericConstraint]

    public init(name: String, constraints: [GenericConstraint] = []) {
        self.name = name
        self.constraints = constraints
    }
}

public struct GenericConstraint: Codable, Equatable, Hashable, Sendable {
    public var kind: Kind
    public var type: TypeReference

    public init(kind: Kind, type: TypeReference) {
        self.kind = kind
        self.type = type
    }

    public enum Kind: String, Codable, Equatable, Hashable, Sendable {
        case conformance
        case superclass
        case sameType
    }
}
