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

    /// Visibility ordering for `--min-access`-style filtering: higher = more visible.
    /// `open > public > packagePrivate > internal > protected > filePrivate > private`.
    ///
    /// Consistent with every supported language: Swift's `package` is broader than `internal`
    /// (`packagePrivate > internal`); Kotlin's `internal` (module-wide) is broader than `protected`
    /// (subclass-only). No language emits both `protected` and `packagePrivate` together, so this
    /// ordering contradicts none of them.
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
