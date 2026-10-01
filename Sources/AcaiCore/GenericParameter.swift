public struct GenericParameter: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var constraints: [GenericConstraint]
    /// Declaration-site variance, where the language marks it on the parameter. `nil` where the language
    /// has no such concept, or where the declaration left it unwritten.
    public var variance: Variance?

    public init(name: String, constraints: [GenericConstraint] = [], variance: Variance? = nil) {
        self.name = name
        self.constraints = constraints
        self.variance = variance
    }
}

/// How a generic parameter may be substituted: `covariant` keeps the subtype direction of its
/// argument, `contravariant` reverses it, `invariant` admits neither.
public enum Variance: String, Codable, Equatable, Hashable, Sendable {
    case covariant
    case contravariant
    case invariant
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
