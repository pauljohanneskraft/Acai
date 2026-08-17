import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

private final class FetchSpy: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var fetchedPaths: [String] = []

    func record(_ path: String) {
        lock.lock()
        fetchedPaths.append(path)
        lock.unlock()
    }
}

@Suite("RepositoryFetchCoordinator")
struct RepositoryFetchCoordinatorTests {
    private func makeCoordinator(
        recencyWindow: TimeInterval = 60, spy: FetchSpy
    ) -> RepositoryFetchCoordinator {
        RepositoryFetchCoordinator(recencyWindow: recencyWindow) { repository, _ in
            spy.record(repository.localPath.path)
        }
    }

    @Test("Two codebases pointing at the same remote fetch it exactly once")
    func dedupsCodebasesSharingOneRemote() async throws {
        let spy = FetchSpy()
        let coordinator = makeCoordinator(spy: spy)
        let store = URL(fileURLWithPath: "/tmp/AcaiTestHub-\(UUID().uuidString)")
        let remoteURL = URL(string: "https://github.com/acme/monorepo.git")!

        let firstReference = CodebaseRepositoryReference(remoteURL: remoteURL, ref: "main")
        let first = Codebase(name: "app", directoryPath: "/a", repository: firstReference)
        let second = Codebase(name: "lib", directoryPath: "/b", repository: firstReference)

        try await coordinator.fetchEachRemoteOnce(for: [first, second], hubStoreDirectory: store)

        #expect(spy.fetchedPaths.count == 1)
    }

    @Test("Two codebases pointing at different remotes each get fetched")
    func fetchesEachDistinctRemote() async throws {
        let spy = FetchSpy()
        let coordinator = makeCoordinator(spy: spy)
        let store = URL(fileURLWithPath: "/tmp/AcaiTestHub-\(UUID().uuidString)")

        let oneReference = CodebaseRepositoryReference(
            remoteURL: URL(string: "https://github.com/acme/one.git")!, ref: "main")
        let twoReference = CodebaseRepositoryReference(
            remoteURL: URL(string: "https://github.com/acme/two.git")!, ref: "main")
        let first = Codebase(name: "app", directoryPath: "/a", repository: oneReference)
        let second = Codebase(name: "lib", directoryPath: "/b", repository: twoReference)

        try await coordinator.fetchEachRemoteOnce(for: [first, second], hubStoreDirectory: store)

        #expect(spy.fetchedPaths.count == 2)
    }

    @Test("A codebase with no repository reference contributes nothing to fetch")
    func skipsCodebasesWithoutARepositoryReference() async throws {
        let spy = FetchSpy()
        let coordinator = makeCoordinator(spy: spy)
        let store = URL(fileURLWithPath: "/tmp/AcaiTestHub-\(UUID().uuidString)")

        let plainFolder = Codebase(name: "local", directoryPath: "/c")

        try await coordinator.fetchEachRemoteOnce(for: [plainFolder], hubStoreDirectory: store)

        #expect(spy.fetchedPaths.isEmpty)
    }

    @Test("A remote fetched within the recency window is skipped on a second call")
    func skipsARecentlyFetchedRemote() async throws {
        let spy = FetchSpy()
        let coordinator = makeCoordinator(recencyWindow: 3_600, spy: spy)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("store", isDirectory: true)
        let remoteURL = URL(string: "https://github.com/acme/monorepo.git")!
        let repository = GitRepository(remoteURL: remoteURL, storeDirectory: store)

        // Simulate an already-fetched shared clone: `GitRepository.lastFetchedAt` reads
        // `.git/FETCH_HEAD`'s mtime, so a real file there (however minimal) is enough.
        try FileManager.default.createDirectory(
            at: repository.localPath.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data().write(to: repository.localPath.appendingPathComponent(".git/FETCH_HEAD"))

        try await coordinator.fetchEachRemoteOnce(among: [repository])

        #expect(spy.fetchedPaths.isEmpty)
    }
}
