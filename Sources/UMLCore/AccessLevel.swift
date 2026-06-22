public enum AccessLevel: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case `public`
    case `open`
    case `internal`
    case protected
    case `private`
    case filePrivate
    case packagePrivate

    public var umlSymbol: String {
        switch self {
        case .public, .open:
            "+"
        case .internal, .packagePrivate:
            "~"
        case .protected:
            "#"
        case .private, .filePrivate:
            "-"
        }
    }

    /// Visibility ordering for `--min-access`-style filtering: higher = more visible. Aligned with
    /// the `umlSymbol` tiers (`+` public > `#` protected > `~` internal/package > `-` private), so
    /// CLI, app, and rendered diagrams all filter consistently from one source of truth.
    public var visibilityRank: Int {
        switch self {
        case .open:
            6
        case .public:
            5
        case .protected:
            4
        case .packagePrivate:
            3
        case .internal:
            2
        case .filePrivate:
            1
        case .private:
            0
        }
    }
}
