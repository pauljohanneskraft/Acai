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
}
