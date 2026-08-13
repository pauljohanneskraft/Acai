/// The glyph palette for a delta (architecture-diff) diagram badge: added `+`, removed `−`, changed
/// `~`, unchanged un-badged. Mirrors `DeltaEdgeColors` — a plain value carrying no diff logic — so a
/// node's changed status reads from its shape/glyph alone, not only from its tint.
public struct DeltaBadgeGlyphs: Sendable {
    /// Added in the new revision.
    public let added: String
    /// Removed since the old revision.
    public let removed: String
    /// Present in both but changed (kind/access/members).
    public let changed: String

    public init(added: String = "+", removed: String = "−", changed: String = "~") {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    /// The conventional `+`/`−`/`~` glyphs.
    public static let standard = DeltaBadgeGlyphs()

    /// The glyph for a status keyword (`added`/`removed`/`changed`), or `nil` for anything else
    /// (e.g. `unchanged`) so those elements get no badge. Takes the raw status string rather than a
    /// `DeltaStatus` so this stays free of the diff layer.
    public func glyph(forStatus status: String) -> String? {
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
