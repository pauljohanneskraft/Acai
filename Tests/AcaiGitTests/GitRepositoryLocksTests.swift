import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiGit

@Suite("GitRepositoryLocks", .timeLimit(.minutes(1)))
struct GitRepositoryLocksTests {
    private actor EventLog {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

    @Test("Two concurrent operations against the same repository never overlap")
    func serializesSameRepository() async throws {
        let repository = GitRepository(
            remoteURL: URL(fileURLWithPath: "/fake/repo"),
            storeDirectory: URL(fileURLWithPath: "/fake/store"))
        let locks = GitRepositoryLocks()
        let log = EventLog()

        let firstHoldsLock = AsyncGate()
        let releaseFirst = AsyncGate()
        let secondEnteredRun = AsyncGate()
        let secondStarted = AsyncGate()

        async let first: Void = locks.run(for: repository) {
            await log.record("first-start")
            await firstHoldsLock.open()
            await releaseFirst.wait()
            await log.record("first-end")
        }
        // Launched before the first demonstrably holds the lock, the second could win the race, and
        // both assertions below would be about the scheduler's choice rather than about the lock.
        // Bounded so a lock that never grants the first operation fails here rather than hanging.
        try await firstHoldsLock.wait(timeout: .seconds(10))

        let second = Task {
            await secondEnteredRun.open()
            try await locks.run(for: repository) {
                await secondStarted.open()
                await log.record("second-start")
                await log.record("second-end")
            }
        }
        await secondEnteredRun.wait()

        // `secondEnteredRun` has already established the second task is running and about to call
        // `locks.run`, so the only thing left to wait out is `acquire()`'s own suspension — which is
        // why a short bound is sound rather than a guess at how slow the runner is. The timeout is the pass.
        await #expect(throws: AsyncGate.TimedOut.self) {
            try await secondStarted.wait(timeout: .milliseconds(200))
        }

        await releaseFirst.open()
        try await second.value
        try await first

        let events = await log.events
        #expect(events == ["first-start", "first-end", "second-start", "second-end"])
    }

    @Test("Operations against different repositories run independently")
    func doesNotSerializeDifferentRepositories() async throws {
        let store = URL(fileURLWithPath: "/fake/store")
        let repositoryA = GitRepository(remoteURL: URL(fileURLWithPath: "/fake/a"), storeDirectory: store)
        let repositoryB = GitRepository(remoteURL: URL(fileURLWithPath: "/fake/b"), storeDirectory: store)
        let locks = GitRepositoryLocks()
        let log = EventLog()

        // A holds its own lock until B has finished. If the two repositories shared a lock, B could
        // never run and `wait(timeout:)` would throw — so independence is proven by the test
        // completing at all, rather than by B beating a sleep A happens to be in.
        let bFinished = AsyncGate()
        async let first: Void = locks.run(for: repositoryA) {
            await log.record("a-start")
            try await bFinished.wait(timeout: .seconds(10))
            await log.record("a-end")
        }
        async let second: Void = locks.run(for: repositoryB) {
            await log.record("b-start")
            await log.record("b-end")
            await bFinished.open()
        }
        _ = try await (first, second)

        let events = await log.events
        #expect(events.firstIndex(of: "b-end")! < events.firstIndex(of: "a-end")!)
    }
}
