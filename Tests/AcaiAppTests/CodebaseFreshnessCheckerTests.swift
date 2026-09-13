import Foundation
import Testing
@testable import AcaiApp

// Fixture helper shells out to real `git` via `Process`, unavailable on iOS.
#if os(macOS)
@Suite("CodebaseFreshnessChecker")
struct CodebaseFreshnessCheckerTests {
    @Test("A plain, non-git folder is fingerprinted by file state")
    func plainFolderUsesFileSystemFingerprint() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let fingerprint = CodebaseFreshnessChecker(directoryPath: dir.path).currentFingerprint()

        guard case .fileSystem = fingerprint else {
            Issue.record("Expected .fileSystem, got \(fingerprint)")
            return
        }
    }

    @Test("A git-backed folder is fingerprinted by its checkout state, dirty or clean")
    func gitFolderUsesGitFingerprint() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try git(["init", "-q", "--initial-branch=main"], in: dir)
        try git(["config", "user.email", "t@t.test"], in: dir)
        try git(["config", "user.name", "Test"], in: dir)
        try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "initial"], in: dir)

        let clean = CodebaseFreshnessChecker(directoryPath: dir.path).currentFingerprint()
        guard case .git(_, let isDirtyWhenClean) = clean else {
            Issue.record("Expected .git, got \(clean)")
            return
        }
        #expect(isDirtyWhenClean == false)

        try "changed".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let dirty = CodebaseFreshnessChecker(directoryPath: dir.path).currentFingerprint()
        guard case .git(_, let isDirtyAfterEdit) = dirty else {
            Issue.record("Expected .git, got \(dirty)")
            return
        }
        #expect(isDirtyAfterEdit == true)
        #expect(clean != dirty)
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodebaseFreshnessCheckerTests-\(UUID().uuidString)", isDirectory: true)
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
