import Foundation
import Testing
@testable import AcaiGit

@Suite("GitRepositoryLocks")
struct GitRepositoryLocksTests {
    /// Records the order operations start and finish in, to prove non-overlap.
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

    @Test("Operations against different repositories run independently")
    func doesNotSerializeDifferentRepositories() async throws {
        let store = URL(fileURLWithPath: "/fake/store")
        let repositoryA = GitRepository(remoteURL: URL(fileURLWithPath: "/fake/a"), storeDirectory: store)
        let repositoryB = GitRepository(remoteURL: URL(fileURLWithPath: "/fake/b"), storeDirectory: store)
        let locks = GitRepositoryLocks()
        let log = EventLog()

        async let first: Void = locks.run(for: repositoryA) {
            await log.record("a-start")
            try await Task.sleep(nanoseconds: 50_000_000)
            await log.record("a-end")
        }
        async let second: Void = locks.run(for: repositoryB) {
            await log.record("b-start")
            await log.record("b-end")
        }
        _ = try await (first, second)

        let events = await log.events
        // "b" (no sleep) finishes well before "a" (long sleep) if they ran independently.
        #expect(events.firstIndex(of: "b-end")! < events.firstIndex(of: "a-end")!)
    }
}
