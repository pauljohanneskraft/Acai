public enum MemberKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case property
    case method
    case initializer
    case deinitializer
    case `subscript`
}
