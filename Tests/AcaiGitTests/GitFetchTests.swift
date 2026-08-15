import Foundation
import Testing
@testable import AcaiGit

/// Thread-safe collector for progress values reported by `GitFetch.run(onProgress:)` — the
/// transfer-progress callback runs synchronously inside the fetch call, but on whatever thread the
/// calling `Task` happens to be running on, so this needs real exclusion rather than a plain array.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

@Suite("GitFetch", .serialized)
struct GitFetchTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("An already-cancelled Task aborts the fetch with CancellationError instead of running to completion")
    func alreadyCancelledTaskAbortsImmediately() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()
        let clone = root.appendingPathComponent("clone", isDirectory: true)
        try await GitClone(remoteURL: source, ref: "main").sync(into: clone)

        let task = Task {
            try await GitFetch(repositoryDirectory: clone).run()
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("A fetch with new upstream objects reports transfer progress through onProgress")
    func reportsTransferProgressForANonTrivialFetch() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()
        let clone = root.appendingPathComponent("clone", isDirectory: true)
        try await GitClone(remoteURL: source, ref: "main").sync(into: clone)

        // Give the upstream remote new commits (and thus new objects) for the fetch below to
        // actually transfer — fetching against an already-up-to-date remote reports no progress at
        // all, which would make this test pass vacuously.
        try "more".write(
            to: source.appendingPathComponent("More.swift"), atomically: true, encoding: .utf8)
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["add", "More.swift"]
        git.currentDirectoryURL = source
        try git.run()
        git.waitUntilExit()
        let commit = Process()
        commit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commit.arguments = ["commit", "-m", "add more"]
        commit.currentDirectoryURL = source
        commit.environment = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com"
        ]
        try commit.run()
        commit.waitUntilExit()

        let collector = ProgressCollector()
        try await GitFetch(repositoryDirectory: clone).run { progress in
            collector.record(progress)
        }

        #expect(!collector.values.isEmpty)
        #expect(collector.values.last == 1.0)
    }
}
