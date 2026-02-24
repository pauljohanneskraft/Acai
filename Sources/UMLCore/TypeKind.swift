public enum TypeKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case interface
    case trait
    case typeAlias
    case object
    case `extension`
    case annotation
    case module
    case record
}
