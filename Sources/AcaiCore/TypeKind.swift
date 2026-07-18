public enum TypeKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case `class`
    case actor
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
    case mixin

    /// The UML stereotype label for this type kind, or `nil` for kinds
    /// that have no stereotype (e.g. `.class`, `.extension`).
    public var stereotypeString: String? {
        switch self {
        case .protocol, .interface:
            "interface"
        case .enum:
            "enumeration"
        case .struct:
            "struct"
        case .typeAlias:
            "typealias"
        case .object:
            "object"
        case .annotation:
            "annotation"
        case .module:
            "module"
        case .trait:
            "trait"
        case .record:
            "record"
        case .mixin:
            "mixin"
        case .actor:
            "actor"
        case .class, .extension:
            nil
        }
    }
}
