import Foundation

/// Counts how often one operation runs, so a regression test can assert an algorithm's shape — a
/// path standardised once per directory, a tree listed once per analysis — instead of timing it on
/// shared CI hardware.
///
/// Injected per instance rather than held statically: `swift test --parallel` runs suites in one
/// process, so a shared counter would mix their totals.
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

    public func reset() {
        lock.withLock { occurrences = 0 }
    }
}
