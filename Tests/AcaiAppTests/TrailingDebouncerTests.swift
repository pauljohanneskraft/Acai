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
@Suite("TrailingDebouncer")
struct TrailingDebouncerTests {
    private func waitUntil(
        timeout: Duration = .seconds(2), pollInterval: Duration = .milliseconds(5), _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }

    @Test("A single trigger fires once after the duration elapses")
    func singleTriggerFiresOnce() async throws {
        let counter = FireCounter()
        let debouncer = TrailingDebouncer(duration: .milliseconds(20)) { counter.increment() }
        debouncer.trigger()
        try await waitUntil { counter.count == 1 }
        #expect(counter.count == 1)
    }

    @Test("A burst of triggers collapses into exactly one fire, timed off the last trigger")
    func burstOfTriggersFiresOnce() async throws {
        let counter = FireCounter()
        let debouncer = TrailingDebouncer(duration: .milliseconds(30)) { counter.increment() }
        for _ in 0..<10 {
            debouncer.trigger()
            try await Task.sleep(for: .milliseconds(5))
        }
        // Still within the debounce window of the last trigger: must not have fired yet.
        // swiftlint:disable:next empty_count
        #expect(counter.count == 0)
        try await waitUntil { counter.count == 1 }
        #expect(counter.count == 1)
    }

    @Test("cancel() suppresses a pending fire")
    func cancelSuppressesAPendingFire() async throws {
        let counter = FireCounter()
        let debouncer = TrailingDebouncer(duration: .milliseconds(20)) { counter.increment() }
        debouncer.trigger()
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(60))
        // swiftlint:disable:next empty_count
        #expect(counter.count == 0)
    }
}
