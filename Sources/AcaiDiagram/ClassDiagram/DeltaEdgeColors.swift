/// The colour palette for a delta (architecture-diff) diagram: added edges green, removed red,
/// changed amber, unchanged untinted. A plain value — like `PackageDiagram`'s distance
/// tint it names no language and carries no diff logic, so it respects the agnostic boundary. The
/// caller maps each element's diff status to one of these and feeds it to a renderer's per-element
/// colour override.
public struct DeltaEdgeColors: Sendable {
    /// Added in the new revision.
    public let added: String
    /// Removed since the old revision.
    public let removed: String
    /// Present in both but changed (multiplicity/label/weight).
    public let changed: String

    public init(added: String = "#2e7d32", removed: String = "#c62828", changed: String = "#f9a825") {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    /// The conventional green/red/amber palette.
    public static let standard = DeltaEdgeColors()

    /// The hex for a status keyword (`added`/`removed`/`changed`), or `nil` for anything else
    /// (e.g. `unchanged`) so those elements keep their default colour. Takes the raw status string
    /// rather than a `DeltaStatus` so this stays free of the diff layer.
    public func hex(forStatus status: String) -> String? {
        switch status {
        case "added":
            return added
        case "removed":
            return removed
        case "changed":
            return changed
        default:
            return nil
        }
    }
}
