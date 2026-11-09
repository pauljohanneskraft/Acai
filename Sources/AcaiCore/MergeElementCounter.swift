import Foundation

/// Injected per ``AnalysisService`` rather than static, so suites running in one process don't mix totals.
public final class MergeElementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var copied = 0

    public init() {}

    public var elementsCopied: Int {
        lock.withLock { copied }
    }

    public func record(_ elements: Int) {
        lock.withLock { copied += elements }
    }
}
