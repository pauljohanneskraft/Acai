import AcaiDiagram

/// The change status of a single graph element (a type node or a relationship edge) between
/// two revisions of a codebase.
public enum DeltaStatus: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case added
    case removed
    case changed
    case unchanged
}

extension DeltaStatus {
    /// `nil` for `.unchanged` so the element keeps its themed colour instead of a delta tint.
    public var deltaHex: String? {
        DeltaEdgeColors.standard.hex(forStatus: rawValue)
    }

    /// Non-color counterpart to `deltaHex`, since status must never be color-only.
    public var badgeGlyph: String? {
        DeltaBadgeGlyphs.standard.glyph(forStatus: rawValue)
    }

    public var badgeAccessibilityLabel: String? {
        badgeGlyph != nil ? rawValue.capitalized : nil
    }
}
