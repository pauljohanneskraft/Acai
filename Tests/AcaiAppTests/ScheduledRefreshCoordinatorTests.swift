import Foundation
import Testing
@testable import AcaiApp

private final class PullSpy: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pulledIDs: [UUID] = []

    func record(_ id: UUID) {
        lock.lock()
        pulledIDs.append(id)
        lock.unlock()
    }
}

@MainActor
@Suite("ScheduledRefreshCoordinator")
struct ScheduledRefreshCoordinatorTests {
    private func makeStore() throws -> ProjectStore {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        return ProjectStore(baseDir: baseDir)
    }

    private func githubCodebase(name: String) -> Codebase {
        var codebase = Codebase(name: name, directoryPath: "/tmp/\(name)")
        codebase.githubSource = GitHubSource(owner: "acme", repo: name, ref: "main")
        return codebase
    }

    @Test("githubBackedCodebaseIDs excludes plain local folders")
    func excludesPlainLocalFolders() throws {
        let store = try makeStore()
        let local = Codebase(name: "local", directoryPath: "/tmp/local")
        let github = githubCodebase(name: "widgets")
        store.projects = [Project(title: "P", subtitle: "", codebases: [local, github])]

        let spy = PullSpy()
        let coordinator = ScheduledRefreshCoordinator(store: store) { id in spy.record(id) }

        #expect(coordinator.githubBackedCodebaseIDs == [github.id])
    }

    @Test("sweepOnce pulls every GitHub-backed codebase")
    func sweepOncePullsEveryGitHubBackedCodebase() async throws {
        let store = try makeStore()
        let first = githubCodebase(name: "one")
        let second = githubCodebase(name: "two")
        store.projects = [Project(title: "P", subtitle: "", codebases: [first, second])]

        let spy = PullSpy()
        let coordinator = ScheduledRefreshCoordinator(store: store) { id in spy.record(id) }

        await coordinator.sweepOnce()

        #expect(Set(spy.pulledIDs) == Set([first.id, second.id]))
    }

    @Test("refreshNext processes one codebase at a time, round-robin, reporting whether more remain")
    func refreshNextRoundRobins() async throws {
        let store = try makeStore()
        let first = githubCodebase(name: "one")
        let second = githubCodebase(name: "two")
        store.projects = [Project(title: "P", subtitle: "", codebases: [first, second])]

        let spy = PullSpy()
        let coordinator = ScheduledRefreshCoordinator(store: store) { id in spy.record(id) }

        let hasMoreAfterFirst = await coordinator.refreshNext()
        #expect(hasMoreAfterFirst)
        #expect(spy.pulledIDs == [first.id])

        let hasMoreAfterSecond = await coordinator.refreshNext()
        #expect(!hasMoreAfterSecond)
        #expect(spy.pulledIDs == [first.id, second.id])

        // Wraps back around to the first codebase.
        let hasMoreAfterWrap = await coordinator.refreshNext()
        #expect(hasMoreAfterWrap)
        #expect(spy.pulledIDs == [first.id, second.id, first.id])
    }

    @Test("refreshNext is a no-op when there are no GitHub-backed codebases")
    func refreshNextIsNoOpWithoutGitHubBackedCodebases() async throws {
        let store = try makeStore()
        let local = Codebase(name: "local", directoryPath: "/tmp/local")
        store.projects = [Project(title: "P", subtitle: "", codebases: [local])]

        let spy = PullSpy()
        let coordinator = ScheduledRefreshCoordinator(store: store) { id in spy.record(id) }

        let hasMore = await coordinator.refreshNext()

        #expect(!hasMore)
        #expect(spy.pulledIDs.isEmpty)
    }
}
