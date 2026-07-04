// Code-smell folds over a type's already-parsed members, exposed as behaviour on the type they
// describe (never a free function / static namespace). Each is a pure, raw-valued fold — no
// thresholds and no language configuration — mirroring the existing coupling/OO metrics. The metrics
// engine (``CodeArtifact/computeMetrics()``) reads these into ``CodeMetrics/TypeMetric``.
extension TypeDeclaration {

    /// Members at least as visible as `public` (public/open) — the type's outward API surface.
    var publicMemberCount: Int {
        members.visible(atLeast: .public).count
    }

    /// Fraction of members that are public/open (0 when the type has no members). A high ratio on a
    /// type with many members is a wide-surface / low-encapsulation smell.
    var publicMemberRatio: Double {
        members.isEmpty ? 0 : Double(publicMemberCount) / Double(members.count)
    }

    /// Count of publicly *settable* stored properties: a stored property whose setter is public/open
    /// (its `setAccessLevel`, or `accessLevel` when the setter isn't narrowed). Publicly mutable state
    /// breaks encapsulation — callers can mutate the type's internals directly.
    var mutablePublicState: Int {
        members.filter { member in
            member.kind == .property && !member.isComputed
                && (member.setAccessLevel ?? member.accessLevel).visibilityRank >= AccessLevel.public.visibilityRank
        }.count
    }

    /// The largest parameter count of any callable member (0 when the type has none). A wide signature
    /// is the long-parameter-list smell — the reader decides "too wide"; no threshold is baked in.
    var maxParameters: Int {
        callableMembers.map(\.parameters.count).max() ?? 0
    }

    /// Mean parameter count across the type's callable members (0 when it has none).
    var meanParameters: Double {
        let counts = callableMembers.map(\.parameters.count)
        return counts.isEmpty ? 0 : Double(counts.reduce(0, +)) / Double(counts.count)
    }

    /// Data-class / anemic score: the share of behaviour-vs-data that is data, `properties / (properties
    /// + methods)` (0 = pure behaviour, 1 = pure data; 0 when the type has neither). A high score on a
    /// type others reach into is the anemic-domain-model smell.
    var dataClassScore: Double {
        let properties = members.filter { $0.kind == .property }.count
        let methods = members.filter { $0.isMethod }.count
        let total = properties + methods
        return total == 0 ? 0 : Double(properties) / Double(total)
    }

    /// Count of members that `override` an inherited member — refused-bequest candidates (a subclass
    /// that overrides much of what it inherits may not truly be a subtype).
    var overrideCount: Int {
        members.filter { $0.modifiers.contains(.override) }.count
    }

    /// Depth of the nested-type tree rooted at this type (0 when it declares no nested types). Deeply
    /// nested types are a comprehension burden.
    var nestingDepth: Int {
        (nestedTypes.map(\.nestingDepth).max()).map { $0 + 1 } ?? 0
    }

    /// Callable members (methods, initializers, subscripts) — the ones that carry a parameter list.
    private var callableMembers: [Member] {
        members.filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .subscript }
    }
}
