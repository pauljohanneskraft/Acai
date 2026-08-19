import Foundation

/// A lock-guarded box for state a test writes from one thread and reads from another — typically a
/// `URLProtocol` subclass recording what it was asked for, read back by the test after `await`.
/// `nonisolated(unsafe)` on a plain `var` expresses the same intent but is a genuine data race.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    public init(_ value: Value) {
        storage = value
    }

    public var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    @discardableResult
    public func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&storage) }
    }
}
