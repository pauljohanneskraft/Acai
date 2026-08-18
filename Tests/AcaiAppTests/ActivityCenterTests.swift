import Foundation
import Testing
@testable import AcaiApp

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
        // Three actor hops sit between this poll and `onProgress` actually landing (the test's own
        // `Task`, `run`'s work `Task`, and `onProgress`'s own reporting `Task`), each contending for
        // the same `@MainActor` serial executor as every other suite running in parallel — a wider
        // margin than `Eventually`'s default is needed here specifically, not because the condition
        // is ever expected to take long, but because a fully-loaded parallel run can push all three
        // hops out further than 2 seconds without any of them being individually stuck.
        try await Eventually(timeout: .seconds(15)).waitUntil { center.operations.first?.progress == 0.5 }
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
