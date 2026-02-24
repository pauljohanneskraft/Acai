public struct Relationship: Codable, Equatable, Hashable, Sendable {
    public var kind: Kind
    public var source: String
    public var target: String
    public var sourceLabel: String?
    public var targetLabel: String?
    public var label: String?

    public init(
        kind: Kind,
        source: String,
        target: String,
        sourceLabel: String? = nil,
        targetLabel: String? = nil,
        label: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.target = target
        self.sourceLabel = sourceLabel
        self.targetLabel = targetLabel
        self.label = label
    }

    public enum Kind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        case inheritance
        case conformance
        case composition
        case aggregation
        case association
        case dependency
        case `extension`
        case nesting
    }
}
