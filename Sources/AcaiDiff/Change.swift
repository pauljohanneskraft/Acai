public struct Change<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var before: T
    public var after: T

    public init(before: T, after: T) {
        self.before = before
        self.after = after
    }

    /// `nil` when either side is absent or the two are equal, so a metric delta can read
    /// `Change(from: old?.x, to: new?.x)` and only get a value when something actually moved.
    public init?(from before: T?, to after: T?) {
        guard let before, let after, before != after else { return nil }
        self.init(before: before, after: after)
    }
}
