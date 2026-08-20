import Foundation

/// Polls a condition instead of sleeping a guessed duration before asserting on it — many async unit
/// tests assert on state set by an unstructured `Task { }`'s body, and nothing bounds how long that
/// takes to even get scheduled under a loaded CI runner. A fixed sleep races that scheduling latency
/// and flakes when it loses; polling only fails if the condition truly never becomes true within
/// `timeout`, which is a real bug rather than a slow runner.
///
/// `@MainActor`: several call sites (e.g. `ActivityCenterTests`) poll `@MainActor`-isolated state
/// directly, so `waitUntil` must run on the same actor as its caller rather than accepting a closure
/// across an actor boundary.
@MainActor
public struct Eventually {
    /// Thrown rather than returned silently: a timeout and a genuine logic bug produce the same
    /// downstream assertion failure otherwise, which is exactly what made past CI flakes here
    /// unexplainable.
    public struct TimedOut: Error, CustomStringConvertible {
        public let description: String
    }

    public var timeout: Duration = .seconds(10)
    public var pollInterval: Duration = .milliseconds(5)

    public init(timeout: Duration = .seconds(10), pollInterval: Duration = .milliseconds(5)) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    public func waitUntil(
        _ description: @autoclosure () -> String = "condition",
        file: String = #fileID, line: Int = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TimedOut(
                    description: "\(file):\(line): timed out after \(timeout) waiting until \(description())"
                )
            }
            try await Task.sleep(for: pollInterval)
        }
    }
}
