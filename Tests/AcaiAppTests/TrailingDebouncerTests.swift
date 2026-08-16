import Foundation
import Testing
@testable import AcaiApp

private final class FireCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

/// Uses millisecond durations throughout so this stays fast and deterministic under
/// `swift test --parallel` — no real-seconds sleeps, matching `ActivityCenterTests`'s own
/// `Eventually` polling pattern rather than a fixed-duration wait racing scheduling latency.
///
/// `@MainActor`: required to use the shared `Eventually` (see its own doc comment) — nothing polled
/// here is main-actor state itself, but `Eventually` must run on the same actor as its caller.
///
/// `Eventually`'s `timeout` is set generously (10s) below despite the debouncer durations under test
/// being tens of milliseconds: on a resource-constrained CI runner, `swift test --parallel` schedules
/// all 232 suites' tasks concurrently against far fewer cores than a dev machine has, so even a 20ms
/// `Task.sleep` inside `TrailingDebouncer.trigger()` can go a full second or more without getting a
/// scheduling turn — a real, previously observed CI failure (`counter.count == 0` after the old,
/// tighter 2s bound), not evidence the debouncer itself failed to fire.
@Suite("TrailingDebouncer")
@MainActor
struct TrailingDebouncerTests {
    /// Waits for `duration` to really elapse, signaled by a throwaway same-duration
    /// `TrailingDebouncer` through `AsyncGate`, rather than guessing a `Task.sleep` length — so a
    /// following negative assertion's only failure mode is `AsyncGate`'s own generous timeout, never
    /// a race against how long the debouncer under test happens to take.
    private func waitForRealElapsed(_ duration: Duration) async throws {
        let gate = AsyncGate()
        let beacon = TrailingDebouncer(duration: duration) { Task { await gate.open() } }
        beacon.trigger()
        try await gate.wait(timeout: .seconds(10))
    }

    @Test("A single trigger fires once after the duration elapses")
    func singleTriggerFiresOnce() async throws {
        let counter = FireCounter()
        let debouncer = TrailingDebouncer(duration: .milliseconds(20)) { counter.increment() }
        debouncer.trigger()
        try await Eventually(timeout: .seconds(10)).waitUntil { counter.count == 1 }
        #expect(counter.count == 1)
    }

    @Test("A burst of triggers collapses into exactly one fire, timed off the last trigger")
    func burstOfTriggersFiresOnce() async throws {
        let counter = FireCounter()
        let debouncer = TrailingDebouncer(duration: .milliseconds(30)) { counter.increment() }
        // No inter-trigger sleep: `trigger()` is synchronous and cancels/reschedules its own pending
        // fire, so a tight back-to-back loop is both a more faithful "burst" and avoids racing a
        // guessed sleep duration against real CI scheduling latency (the previous inter-trigger
        // `Task.sleep` could itself run long enough to let the debounce window elapse mid-burst).
        for _ in 0..<10 {
            debouncer.trigger()
        }
        try await Eventually(timeout: .seconds(10)).waitUntil { counter.count >= 1 }
        // A debouncer that doesn't actually collapse the burst (fires per-trigger, or fires the
        // first trigger too) would keep incrementing past 1 — wait a further real debounce window
        // (via `waitForRealElapsed`, not a guessed sleep) before asserting the final count, so that
        // failure mode is caught here rather than by `waitUntil` getting lucky on a transient `== 1`.
        try await waitForRealElapsed(.milliseconds(30))
        #expect(counter.count == 1)
    }

    @Test("cancel() suppresses a pending fire")
    func cancelSuppressesAPendingFire() async throws {
        let counter = FireCounter()
        let debouncer = TrailingDebouncer(duration: .milliseconds(20)) { counter.increment() }
        debouncer.trigger()
        debouncer.cancel()
        try await waitForRealElapsed(.milliseconds(60))
        // swiftlint:disable:next empty_count
        #expect(counter.count == 0)
    }
}
