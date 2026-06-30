/// A directed edge between two types in the diagram graph (inheritance, composition, a dependency,
/// …). Produced by parsers and resolved/deduplicated during enrichment; consumed by the diagram and
/// metrics layers.
public struct Relationship: Codable, Equatable, Hashable, Sendable {
    /// The semantic edge kind — selects the arrowhead/line style the diagram draws and the
    /// precedence used when redundant edges between the same pair are collapsed (see `Kind`).
    public var kind: Kind
    /// Identity of the edge's tail type. Parsers may emit a name; enrichment resolves it to a type
    /// `id` via the name→id index. An endpoint that resolves to no known type stays as the bare name
    /// and renders as an external node.
    public var source: String
    /// Identity of the edge's head type. Resolved the same way as `source`.
    public var target: String
    /// Optional multiplicity/role label shown at the `source` end (e.g. `1`, `0..*`).
    public var sourceLabel: String?
    /// Optional multiplicity/role label shown at the `target` end.
    public var targetLabel: String?
    /// Optional label shown along the edge (e.g. the member name behind an association).
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

    /// The semantic kinds of edge the engine distinguishes. Redundant-edge collapsing keeps the
    /// strongest kind between a pair, in roughly this order: inheritance/conformance/extension >
    /// composition/aggregation > association > dependency.
    public enum Kind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        /// Class/`extends` inheritance (solid line, hollow triangle).
        case inheritance
        /// Protocol/interface conformance or `implements` (dashed line, hollow triangle).
        case conformance
        /// Strong "owns" containment — a stored property of a non-shared value type (filled diamond).
        case composition
        /// Weak "has-a" reference — a stored property of a reference/shared type (hollow diamond).
        case aggregation
        /// A named link weaker than aggregation (plain line).
        case association
        /// A use/construction/parameter dependency, not a stored relationship (dashed arrow).
        case dependency
        /// An `extension`/category augmenting an existing type.
        case `extension`
        /// A type nested inside another (`Outer.Inner`).
        case nesting
    }
}
