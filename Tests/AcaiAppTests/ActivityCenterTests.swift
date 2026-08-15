import Foundation
import Testing
@testable import AcaiApp

/// Polls a condition instead of sleeping a guessed duration before asserting on it — the tests below
/// assert on state set by an unstructured `Task { }`'s body, and nothing bounds how long that takes
/// to even get scheduled onto the main actor under a loaded CI runner. A fixed sleep races that
/// scheduling latency and flakes when it loses; polling only fails if the condition truly never
/// becomes true within `timeout`, which is a real bug rather than a slow runner.
///
/// `@MainActor`, matching `ActivityCenterTests` below: the conditions it polls read `ActivityCenter`
/// state directly, so `waitUntil` must run on the same actor as its caller rather than accepting a
/// closure across an actor boundary.
@MainActor
private struct Eventually {
    var timeout: Duration = .seconds(2)
    var pollInterval: Duration = .milliseconds(5)

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }
}

/// A one-shot signal an in-flight operation can `wait()` on, so a test can hold an operation open
/// until it has actually observed the state it's asserting on — a fixed `Task.sleep` races the
/// scheduling latency `Eventually` above is designed to avoid, and flakes under a loaded parallel
/// test run for the same reason.
private actor AsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

/// The generic in-flight-operation registry. Covers the three contracts every call site
/// (`reindex`, `pull`, `switchGitHubRef`, `addGitHubCodebase`, `RepositoryDetailView.fetchNow`)
/// relies on: the row disappears once `run` returns, `isBusy(_:)` is true for exactly the right
/// subject while work is outstanding, and cancelling discards the result rather than throwing or
/// silently applying a stale value.
@Suite("ActivityCenter")
@MainActor
struct ActivityCenterTests {
    @Test func runReturnsTheOperationsResultAndClearsTheRowWhenDone() async throws {
        let center = ActivityCenter()
        let result = try await center.run(title: "Test", kind: .reindex) {
            42
        }
        #expect(result == 42)
        #expect(center.operations.isEmpty)
    }

    @Test func isBusyReflectsAnInFlightOperationForItsSubjectOnly() async throws {
        let center = ActivityCenter()
        let codebaseID = UUID()
        let otherCodebaseID = UUID()
        let gate = AsyncGate()
        let task = Task {
            try await center.run(title: "Indexing…", kind: .reindex, subject: .codebase(codebaseID)) {
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil { center.isBusy(.codebase(codebaseID)) }
        #expect(center.isBusy(.codebase(codebaseID)))
        #expect(!center.isBusy(.codebase(otherCodebaseID)))
        await gate.open()
        _ = try await task.value
        #expect(!center.isBusy(.codebase(codebaseID)))
    }

    @Test func cancellingDiscardsTheResultRatherThanThrowingOrApplyingIt() async throws {
        let center = ActivityCenter()
        let task = Task {
            try await center.run(title: "Test", kind: .gitFetch) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return 1
            }
        }
        try await Eventually().waitUntil { !center.operations.isEmpty }
        guard let operation = center.operations.first else {
            Issue.record("expected an in-flight operation to be registered")
            return
        }
        center.cancel(operation.id)
        let result = try await task.value
        #expect(result == nil)
        #expect(center.operations.isEmpty)
    }

    @Test func progressOverloadPublishesReportedValuesOnTheRow() async throws {
        let center = ActivityCenter()
        let gate = AsyncGate()
        let task = Task {
            try await center.run(title: "Fetching…", kind: .gitFetch) { onProgress in
                onProgress(0.5)
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil { center.operations.first?.progress == 0.5 }
        #expect(center.operations.first?.progress == 0.5)
        await gate.open()
        _ = try await task.value
        #expect(center.operations.isEmpty)
    }

    @Test func aThrownErrorPropagatesWhenNotCancelled() async {
        struct TestFailure: Error {}
        let center = ActivityCenter()
        await #expect(throws: TestFailure.self) {
            _ = try await center.run(title: "Test", kind: .reindex) {
                throw TestFailure()
            }
        }
        #expect(center.operations.isEmpty)
    }
}
