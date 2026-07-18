import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("Git revision snapshot")
struct GitRevisionSnapshotTests {

    /// `git archive`-based snapshot returns the artifact as it was at the committed revision, while
    /// a plain analysis of the same directory sees the (uncommitted) working-tree edit — and the
    /// working tree is never mutated by taking the snapshot.
    @Test func snapshotReflectsCommittedRevisionNotWorkingTree() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("model.swift")

        try "class Foo {}\n".write(to: source, atomically: true, encoding: .utf8)
        try git(["init", "-q"], in: dir)
        try git(["config", "user.email", "t@t.test"], in: dir)
        try git(["config", "user.name", "Test"], in: dir)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "initial"], in: dir)

        // Edit the working tree (uncommitted): rename Foo → Bar.
        try "class Bar {}\n".write(to: source, atomically: true, encoding: .utf8)

        let old = try GitRevisionSnapshot(directory: dir, reference: "HEAD").artifact()
        let new = try CodebaseAnalyzer().enrichedArtifact(at: dir)

        #expect(old.types.contains { $0.name == "Foo" })
        #expect(!old.types.contains { $0.name == "Bar" })
        #expect(new.types.contains { $0.name == "Bar" })

        // The working tree still holds the uncommitted edit (snapshot was read-only).
        let onDisk = try String(contentsOf: source, encoding: .utf8)
        #expect(onDisk.contains("Bar"))
    }

    @Test func nonGitDirectoryThrows() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: (any Error).self) {
            _ = try GitRevisionSnapshot(directory: dir, reference: "HEAD").artifact()
        }
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
