import Foundation
import Testing
@testable import AcaiApp

private final class ReindexSpy: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var reindexedIDs: [UUID] = []

    func record(_ id: UUID) {
        lock.lock()
        reindexedIDs.append(id)
        lock.unlock()
    }
}

/// `FileWatchReindexCoordinator` on macOS routes through the real `DirectoryChangeWatcher`
/// (`DispatchSource.makeFileSystemObjectSource`) — these are lightweight filesystem integration
/// tests, not pure unit tests, but a short debounce keeps them fast.
@MainActor
@Suite("FileWatchReindexCoordinator")
struct FileWatchReindexCoordinatorTests {
    private func waitUntil(
        timeout: Duration = .seconds(5), pollInterval: Duration = .milliseconds(20), _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Writing into a watched local folder triggers a full reindex, debounced")
    func writingIntoAWatchedFolderTriggersReindex() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codebaseID = UUID()
        let spy = ReindexSpy()
        let coordinator = FileWatchReindexCoordinator(debounce: .milliseconds(50)) { id in spy.record(id) }

        coordinator.sync(codebases: [Codebase(id: codebaseID, name: "local", directoryPath: root.path)])

        try "content".write(to: root.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)

        try await waitUntil { spy.reindexedIDs.contains(codebaseID) }
        #expect(spy.reindexedIDs == [codebaseID])
        coordinator.stopAll()
    }

    @Test("A GitHub-backed codebase is never watched")
    func githubBackedCodebaseIsNeverWatched() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codebaseID = UUID()
        let spy = ReindexSpy()
        let coordinator = FileWatchReindexCoordinator(debounce: .milliseconds(50)) { id in spy.record(id) }

        var codebase = Codebase(id: codebaseID, name: "github", directoryPath: root.path)
        codebase.githubSource = GitHubSource(owner: "acme", repo: "widgets", ref: "main")
        coordinator.sync(codebases: [codebase])

        try "content".write(to: root.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(200))

        #expect(spy.reindexedIDs.isEmpty)
        coordinator.stopAll()
    }

    @Test("Removing a codebase stops watching it")
    func removingACodebaseStopsWatchingIt() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codebaseID = UUID()
        let spy = ReindexSpy()
        let coordinator = FileWatchReindexCoordinator(debounce: .milliseconds(50)) { id in spy.record(id) }

        coordinator.sync(codebases: [Codebase(id: codebaseID, name: "local", directoryPath: root.path)])
        coordinator.sync(codebases: [])

        try "content".write(to: root.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(200))

        #expect(spy.reindexedIDs.isEmpty)
        coordinator.stopAll()
    }
}
