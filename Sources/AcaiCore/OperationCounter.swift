import Foundation

/// Counts how often one operation runs, so a test can assert an algorithm's shape instead of timing it.
public final class OperationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var occurrences = 0

    public init() {}

    public var count: Int {
        lock.withLock { occurrences }
    }

    public func record() {
        lock.withLock { occurrences += 1 }
    }
}
