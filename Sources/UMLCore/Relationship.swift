public struct Relationship: Codable, Equatable, Hashable, Sendable {
    public var kind: Kind
    public var source: String
    public var target: String
    public var sourceLabel: String?
    public var targetLabel: String?
    public var label: String?
    /// File path of the declaration that *produced* this edge (e.g. the member or extension that
    /// references `target`), when known. Provenance only: an edge inferred from an extension on a
    /// foreign type originates in the extension's file, not the source type's home file — which is
    /// what makes module attribution correct for cross-module extensions. It is deliberately
    /// **excluded from identity** (`==`/`hash`): two edges between the same pair are "the same edge"
    /// regardless of which file declared them, so dedup, diffing and set membership ignore it.
    public var origin: String?

    public init(
        kind: Kind,
        source: String,
        target: String,
        sourceLabel: String? = nil,
        targetLabel: String? = nil,
        label: String? = nil,
        origin: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.target = target
        self.sourceLabel = sourceLabel
        self.targetLabel = targetLabel
        self.label = label
        self.origin = origin
    }

    /// Identity ignores `origin` (provenance metadata, not part of what the edge *is*).
    public static func == (lhs: Relationship, rhs: Relationship) -> Bool {
        lhs.kind == rhs.kind && lhs.source == rhs.source && lhs.target == rhs.target
            && lhs.sourceLabel == rhs.sourceLabel && lhs.targetLabel == rhs.targetLabel
            && lhs.label == rhs.label
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(source)
        hasher.combine(target)
        hasher.combine(sourceLabel)
        hasher.combine(targetLabel)
        hasher.combine(label)
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
