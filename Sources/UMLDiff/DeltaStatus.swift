import UMLDiagram

/// The change status of a single graph element (a type node or a relationship edge) between
/// two revisions of a codebase. Used both by the textual changelog and to tint edges/nodes in a
/// delta diagram.
public enum DeltaStatus: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// Present only in the new revision.
    case added
    /// Present only in the old revision.
    case removed
    /// Present in both, but with differing detail (labels, kind, access, members).
    case changed
    /// Present and identical in both revisions.
    case unchanged
}

extension DeltaStatus {
    /// The delta tint hex for this status (added green / removed red / changed amber), or `nil` for
    /// `.unchanged` so the element keeps its themed colour. The single source for the
    /// `DeltaStatus → DeltaEdgeColors` mapping that every renderer and CLI/app call site shares.
    public var deltaHex: String? {
        DeltaEdgeColors.standard.hex(forStatus: rawValue)
    }
}
