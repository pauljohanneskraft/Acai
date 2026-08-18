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
struct Eventually {
    var timeout: Duration = .seconds(2)
    var pollInterval: Duration = .milliseconds(5)

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }
}
