import AcaiTestSupport
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
/// tests, not pure unit tests, but a short debounce keeps them fast. iOS routes through
/// `DirectoryPollingWatcher` instead (coarser directory-mtime polling, by design), which these
/// short-debounce/15s-timeout tests aren't tuned for — macOS-only.
#if os(macOS)
@MainActor
@Suite("FileWatchReindexCoordinator")
struct FileWatchReindexCoordinatorTests {
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

        try await Eventually(timeout: .seconds(15)).waitUntil { spy.reindexedIDs.contains(codebaseID) }
        #expect(Set(spy.reindexedIDs) == [codebaseID])
        coordinator.stopAll()
    }

    /// A GitHub-backed codebase is never watched at all, so no debounce timer ever starts for it —
    /// there is nothing to poll for or settle-signal on regarding *that* codebase specifically. A
    /// real, still-watched control codebase in the same `sync()` call gives a genuine settle signal
    /// (its own debounce window elapsing, via `didFinishDebounceWindow`) to wait on instead of a
    /// blind sleep, and doubles as a positive check that watching still works for the codebase that
    /// should be watched.
    @Test("A GitHub-backed codebase is never watched")
    func githubBackedCodebaseIsNeverWatched() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controlRoot = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: controlRoot) }
        let codebaseID = UUID()
        let controlID = UUID()
        let spy = ReindexSpy()
        let gate = AsyncGate()
        let coordinator = FileWatchReindexCoordinator(
            debounce: .milliseconds(50),
            didFinishDebounceWindow: { Task { await gate.open() } },
            reindex: { id in spy.record(id) }
        )

        var codebase = Codebase(id: codebaseID, name: "github", directoryPath: root.path)
        codebase.githubSource = GitHubSource(owner: "acme", repo: "widgets", ref: "main")
        let control = Codebase(id: controlID, name: "control", directoryPath: controlRoot.path)
        coordinator.sync(codebases: [codebase, control])

        try "content".write(to: root.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)
        try "content".write(to: controlRoot.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)

        try await gate.wait(timeout: .seconds(15))
        #expect(Set(spy.reindexedIDs) == [controlID])
        coordinator.stopAll()
    }

    /// Same reasoning as `githubBackedCodebaseIsNeverWatched` above: once removed, no debounce timer
    /// ever starts for the removed codebase, so a still-watched control codebase provides the real
    /// settle signal — which also proves removal is selective rather than stopping every watcher.
    @Test("Removing a codebase stops watching it")
    func removingACodebaseStopsWatchingIt() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controlRoot = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: controlRoot) }
        let codebaseID = UUID()
        let controlID = UUID()
        let spy = ReindexSpy()
        let gate = AsyncGate()
        let coordinator = FileWatchReindexCoordinator(
            debounce: .milliseconds(50),
            didFinishDebounceWindow: { Task { await gate.open() } },
            reindex: { id in spy.record(id) }
        )

        let control = Codebase(id: controlID, name: "control", directoryPath: controlRoot.path)
        coordinator.sync(codebases: [Codebase(id: codebaseID, name: "local", directoryPath: root.path), control])
        coordinator.sync(codebases: [control])

        try "content".write(to: root.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)
        try "content".write(to: controlRoot.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)

        try await gate.wait(timeout: .seconds(15))
        #expect(Set(spy.reindexedIDs) == [controlID])
        coordinator.stopAll()
    }
}
#endif
