import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiGit

@Suite("GitRepositoryLocks")
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

        async let first: Void = locks.run(for: repository) {
            await log.record("first-start")
            try await Task.sleep(nanoseconds: 20_000_000)
            await log.record("first-end")
        }
        async let second: Void = locks.run(for: repository) {
            await log.record("second-start")
            try await Task.sleep(nanoseconds: 20_000_000)
            await log.record("second-end")
        }
        _ = try await (first, second)

        let events = await log.events
        // Whichever ran first, its "-end" must precede the other's "-start" — no interleaving.
        let firstIndex = events.firstIndex(of: "first-start")!
        let secondIndex = events.firstIndex(of: "second-start")!
        if firstIndex < secondIndex {
            #expect(events.firstIndex(of: "first-end")! < secondIndex)
        } else {
            #expect(events.firstIndex(of: "second-end")! < firstIndex)
        }
    }

    @Test("Cancelling a queued operation throws immediately, without waiting its turn or blocking the next waiter")
    func cancellingAQueuedOperationThrowsImmediately() async throws {
        let repository = GitRepository(
            remoteURL: URL(fileURLWithPath: "/fake/repo"),
            storeDirectory: URL(fileURLWithPath: "/fake/store"))
        let locks = GitRepositoryLocks()
        let log = EventLog()
        let firstIsRunning = AsyncGate()
        let releaseFirst = AsyncGate()

        let first = Task {
            try await locks.run(for: repository) {
                await log.record("first-start")
                await firstIsRunning.open()
                try await releaseFirst.wait(timeout: .seconds(10))
                await log.record("first-end")
            }
        }
        try await firstIsRunning.wait(timeout: .seconds(10))

        let cancelled = Task {
            try await locks.run(for: repository) {
                await log.record("cancelled-ran")
            }
        }
        // Gives the cancelled task a moment to actually register as a queued waiter before cancelling it.
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelled.cancel()

        // Resolves while `first` is still holding the lock — proving cancellation doesn't wait its turn.
        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }

        async let second: Void = locks.run(for: repository) {
            await log.record("second-start")
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await releaseFirst.open()
        _ = try await first.value
        try await second

        let events = await log.events
        #expect(!events.contains("cancelled-ran"))
        #expect(events.contains("second-start"))
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
