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

    /// Visibility ordering for `--min-access`-style filtering: higher = more visible. A single total
    /// order shared by CLI, app, and rendered diagrams so they filter consistently from one source of
    /// truth: `open > public > packagePrivate > internal > protected > filePrivate > private`.
    ///
    /// This is consistent with every supported language's own lattice, because the only pairs that
    /// actually co-occur pin a single chain: Swift emits `package` and `internal` (`package` is the
    /// broader, so `packagePrivate > internal`), and Kotlin emits `internal` and `protected`
    /// (`internal` is module-wide vs. subclass-only, so `internal > protected`). No language emits
    /// both `protected` and `packagePrivate` — Java's package-private default maps to no access level
    /// (`nil`), not `.packagePrivate` — so placing `protected` just below `internal` contradicts none
    /// of them; everywhere else `protected` only needs to sit below `public` and above `private`.
    public var visibilityRank: Int {
        switch self {
        case .open:
            6
        case .public:
            5
        case .packagePrivate:
            4
        case .internal:
            3
        case .protected:
            2
        case .filePrivate:
            1
        case .private:
            0
        }
    }
}
