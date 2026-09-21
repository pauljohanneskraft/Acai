import Foundation
import Testing
@testable import AcaiCore

@Suite("SourceTreeFingerprint")
struct SourceTreeFingerprintTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceTreeFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Computing twice over unchanged content gives the same fingerprint")
    func stableAcrossRepeatedComputation() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let first = SourceTreeFingerprint(directory: dir).compute()
        let second = SourceTreeFingerprint(directory: dir).compute()
        #expect(first == second)
    }

    @Test("Editing a file's content changes the fingerprint")
    func detectsAnEditedFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let before = SourceTreeFingerprint(directory: dir).compute()

        // Back-date the original write so a fast test run can't land both writes in the same
        // filesystem-timestamp tick, which would mask the change from a pure mtime comparison.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: file.path)
        try "goodbye!!!".write(to: file, atomically: true, encoding: .utf8)

        let after = SourceTreeFingerprint(directory: dir).compute()
        #expect(before != after)
    }

    @Test("Adding a file changes the fingerprint and the file count")
    func detectsAnAddedFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let before = SourceTreeFingerprint(directory: dir).compute()

        try "world".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let after = SourceTreeFingerprint(directory: dir).compute()

        #expect(before != after)
        guard case .fileSystem(_, let count, _) = after else {
            Issue.record("Expected .fileSystem, got \(after)")
            return
        }
        #expect(count == 2)
    }

    @Test("A skipped build-output directory's contents don't affect the fingerprint")
    func skipsBuildOutputDirectories() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let before = SourceTreeFingerprint(directory: dir).compute()

        let nodeModules = dir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try "vendored".write(to: nodeModules.appendingPathComponent("lib.js"), atomically: true, encoding: .utf8)
        let after = SourceTreeFingerprint(directory: dir).compute()

        #expect(before == after)
    }

    @Test("A single file (a stored .json baseline) fingerprints as one entry")
    func fingerprintsASingleFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("baseline.json")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        guard case .fileSystem(_, let count, _) = SourceTreeFingerprint(directory: file).compute() else {
            Issue.record("Expected .fileSystem")
            return
        }
        #expect(count == 1)
    }
}
