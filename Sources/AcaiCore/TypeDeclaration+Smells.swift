// Code-smell folds over a type's already-parsed members. Each is a pure, raw-valued fold — no
// thresholds, no language configuration. Read by ``CodeArtifact/computeMetrics()`` into
// ``CodeMetrics/TypeMetric``.
extension TypeDeclaration {

    var publicMemberCount: Int {
        members.visible(atLeast: .public).count
    }

    /// A high ratio on a type with many members is a wide-surface / low-encapsulation smell.
    var publicMemberRatio: Double {
        members.isEmpty ? 0 : Double(publicMemberCount) / Double(members.count)
    }

    /// Count of publicly *settable* stored properties: a stored property whose setter is public/open
    /// (its `setAccessLevel`, or `accessLevel` when the setter isn't narrowed). Publicly mutable state
    /// breaks encapsulation — callers can mutate the type's internals directly.
    var mutablePublicState: Int {
        members.filter(\.isPubliclySettable).count
    }

    /// The long-parameter-list smell — the reader decides "too wide"; no threshold is baked in.
    var maxParameters: Int {
        callableMembers.map(\.parameters.count).max() ?? 0
    }

    var meanParameters: Double {
        let counts = callableMembers.map(\.parameters.count)
        return counts.isEmpty ? 0 : Double(counts.reduce(0, +)) / Double(counts.count)
    }

    /// Data-class / anemic score: `stored properties / (stored + behaviour)` (0 = pure behaviour,
    /// 1 = pure data). Computed properties count as behaviour (their getter is code) — so a SwiftUI
    /// `View`'s `body` doesn't read as data. A high score on a type others reach into is the
    /// anemic-domain-model smell.
    var dataClassScore: Double {
        let stored = members.filter(\.isStoredProperty).count
        let behaviour = members.filter(\.isBehaviour).count
        let total = stored + behaviour
        return total == 0 ? 0 : Double(stored) / Double(total)
    }

    /// Refused-bequest candidates — a subclass that overrides much of what it inherits may not
    /// truly be a subtype.
    var overrideCount: Int {
        members.filter { $0.modifiers.contains(.override) }.count
    }

    var nestingDepth: Int {
        (nestedTypes.map(\.nestingDepth).max()).map { $0 + 1 } ?? 0
    }

    private var callableMembers: [Member] {
        members.filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .subscript }
    }
}
