/// Flags dependency cycles as violations. MVP evaluates module-level cycles.
public struct CycleRule: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, Sendable, CaseIterable {
        case modules
        case types
    }

    public var scope: Scope

    public init(scope: Scope = .modules) {
        self.scope = scope
    }
}
