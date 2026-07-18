/// A before/after pair for a single scalar that changed.
public struct Change<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var before: T
    public var after: T

    public init(before: T, after: T) {
        self.before = before
        self.after = after
    }

    /// A change only when both sides exist and actually differ; `nil` otherwise (equal, or absent
    /// on one side). Lets a metric delta read `Change(from: old?.x, to: new?.x)`.
    public init?(from before: T?, to after: T?) {
        guard let before, let after, before != after else { return nil }
        self.init(before: before, after: after)
    }
}
