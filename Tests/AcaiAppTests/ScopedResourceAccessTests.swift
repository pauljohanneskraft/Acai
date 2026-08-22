import Foundation
import Testing
@testable import AcaiApp

/// The sandbox denial itself can't be reproduced in the SwiftPM test process (it isn't sandboxed),
/// so these cover everything around it: the plain-path fallback, the probe that turns an
/// unreachable directory into a specific error instead of an empty file list, and the bookmark
/// round-trip that follows a folder to a new location.
@Suite("ScopedResourceAccess")
struct ScopedResourceAccessTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScopedResourceAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    @Test("Without a bookmark, a readable directory resolves to its plain path")
    func plainPathResolves() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolved = try ScopedResourceAccess(path: dir.path, bookmark: nil).withResolvedURL { $0 }

        #expect(resolved.standardizedFileURL.path == dir.path)
    }

    @Test("A directory that no longer exists throws, rather than reporting an empty codebase")
    func missingDirectoryThrows() throws {
        let dir = try makeTempDirectory()
        try FileManager.default.removeItem(at: dir)

        #expect(throws: ScopedResourceAccess.Failure.directoryUnavailable(dir.path)) {
            _ = try ScopedResourceAccess(path: dir.path, bookmark: nil).withResolvedURL { $0 }
        }
    }

    @Test("A bookmark that can't be resolved falls back to the still-readable plain path")
    func unresolvableBookmarkFallsBackToPath() throws {
        let gone = try makeTempDirectory()
        let bookmark = try SecurityScopedBookmark(resolving: gone)
        try FileManager.default.removeItem(at: gone)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolved = try ScopedResourceAccess(path: dir.path, bookmark: bookmark).withResolvedURL { $0 }

        #expect(resolved.standardizedFileURL.path == dir.path)
    }

    @Test("A file path resolves; the probe only applies to directories")
    func filePathResolves() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("rules.yaml")
        try "rules: []\n".write(to: file, atomically: true, encoding: .utf8)

        let resolved = try ScopedResourceAccess(path: file.path, bookmark: nil).withResolvedURL { $0 }

        #expect(resolved.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    @Test("A bookmark follows a renamed folder and reports the new location for persisting")
    func bookmarkFollowsRenamedFolder() throws {
        let dir = try makeTempDirectory()
        let bookmark = try SecurityScopedBookmark(resolving: dir)
        let moved = dir.deletingLastPathComponent()
            .appendingPathComponent("\(dir.lastPathComponent)-moved", isDirectory: true)
        try FileManager.default.moveItem(at: dir, to: moved)
        defer { try? FileManager.default.removeItem(at: moved) }

        var refreshed: ScopedResourceAccess.Refreshed?
        let resolved = try ScopedResourceAccess(path: dir.path, bookmark: bookmark)
            .withResolvedURL(onRefresh: { refreshed = $0 }, { $0 })

        #expect(resolved.standardizedFileURL.path == moved.standardizedFileURL.path)
        #expect(refreshed?.url.standardizedFileURL.path == moved.standardizedFileURL.path)
    }
}
