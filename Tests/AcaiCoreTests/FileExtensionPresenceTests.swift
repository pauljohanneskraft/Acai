import Foundation
import Testing
@testable import AcaiCore

/// `fileExtensionsPresent` answers "are there sources here?" for project discovery, which asks it at
/// every directory it walks — so it has to agree with `fileURLs` about what counts as a source file.
@Suite("File extension presence")
struct FileExtensionPresenceTests {

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("extension-presence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.standardizedFileURL)
    }

    private func write(_ relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// file".write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func reportsOnlyTheExtensionsThatAreActuallyThere() throws {
        try withTempDir { root in
            try write("deep/nested/a.swift", in: root)
            try write("b.PY", in: root)
            let found = FileManager.default.fileExtensionsPresent(
                in: root, among: ["swift", "py", "kt"])

            #expect(found == ["swift", "py"])
        }
    }

    @Test func agreesWithFileURLsAboutExcludedDirectoriesAndHiddenFiles() throws {
        try withTempDir { root in
            try write("node_modules/dep/a.js", in: root)
            try write(".hidden/b.js", in: root)
            let excluded: Set<String> = ["node_modules"]

            #expect(FileManager.default.fileExtensionsPresent(
                in: root, among: ["js"], excludingDirectories: excluded).isEmpty)
            #expect(FileManager.default.fileURLs(
                in: root, withExtensions: ["js"], excludingDirectories: excluded).isEmpty)
        }
    }

    @Test func anEmptyRequestWalksNothing() throws {
        try withTempDir { root in
            try write("a.swift", in: root)
            #expect(FileManager.default.fileExtensionsPresent(in: root, among: []).isEmpty)
        }
    }
}
