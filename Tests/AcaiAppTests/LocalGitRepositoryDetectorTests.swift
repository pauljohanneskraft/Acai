import Foundation
import Testing
@testable import AcaiApp

// Fixture helper shells out to real `git` via `Process`, unavailable on iOS.
#if os(macOS)
@Suite("Local-folder git detection")
struct LocalGitRepositoryDetectorTests {
    @Test func plainNonGitFolderDetectsNothing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(LocalGitRepositoryDetector(directory: dir).detect() == nil)
    }

    @Test func gitFolderWithNoOriginRemoteDetectsNothing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try git(["init", "-q"], in: dir)
        try git(["config", "user.email", "t@t.test"], in: dir)
        try git(["config", "user.name", "Test"], in: dir)
        try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "initial"], in: dir)

        // No `git remote add origin ...` — nothing to sync a shared `GitRepository` against.
        #expect(LocalGitRepositoryDetector(directory: dir).detect() == nil)
    }

    @Test func gitFolderWithOriginRemoteResolvesRemoteURLAndBranch() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try git(["init", "-q", "--initial-branch=main"], in: dir)
        try git(["config", "user.email", "t@t.test"], in: dir)
        try git(["config", "user.name", "Test"], in: dir)
        try git(["remote", "add", "origin", "https://example.test/owner/repo.git"], in: dir)
        try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "initial"], in: dir)

        let reference = LocalGitRepositoryDetector(directory: dir).detect()

        #expect(reference?.remoteURL == URL(string: "https://example.test/owner/repo.git"))
        #expect(reference?.ref == "main")
        #expect(reference?.subpath == nil)
    }

    @Test func pickingASubdirectoryOfARepositoryRecordsItAsTheSubpath() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try git(["init", "-q", "--initial-branch=main"], in: dir)
        try git(["config", "user.email", "t@t.test"], in: dir)
        try git(["config", "user.name", "Test"], in: dir)
        try git(["remote", "add", "origin", "https://example.test/owner/repo.git"], in: dir)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("packages/core"), withIntermediateDirectories: true)
        try "hello".write(
            to: dir.appendingPathComponent("packages/core/README.md"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "initial"], in: dir)

        let subdirectory = dir.appendingPathComponent("packages/core", isDirectory: true)
        let reference = LocalGitRepositoryDetector(directory: subdirectory).detect()

        #expect(reference?.subpath == "packages/core")
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiAppGitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }
}
#endif
