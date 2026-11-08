import Foundation

/// Counts the array elements ``CodeArtifact/init(merging:countingInto:)`` copies, so a regression
/// test can assert the merge stays linear in the corpus instead of timing it on shared CI hardware.
///
/// Injected per ``AnalysisService`` instance rather than held statically: `swift test --parallel`
/// runs suites in one process, so a shared counter would mix their totals.
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

    public func reset() {
        lock.withLock { copied = 0 }
    }
}
