import Foundation
import Testing
@testable import AcaiApp

/// `Codebase.resolvedFileURL(relativePath:)` — the one accessor `ViolationRowView`'s "View Source"
/// button resolves a `SourceLocation.filePath` through. These exercise the same
/// path-escape guarantees as `PathEscapeGuardTests`, but through the actual public entry point
/// (no bookmark, so `ScopedResourceAccess` takes its plain-path fallback) plus the file-existence
/// check `resolvedFileURL` adds on top of `PathEscapeGuard`.
@Suite("Codebase.resolvedFileURL")
struct CodebaseSourceViewerTests {

    private func makeCodebase(at directory: URL) -> Codebase {
        Codebase(name: "Fixture", directoryPath: directory.path)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodebaseSourceViewerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A valid relative path to an existing file resolves")
    func validPathResolves() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "class Foo {}\n".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)

        let url = try makeCodebase(at: dir).resolvedFileURL(relativePath: "Foo.swift")

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A '../'-escaping path is rejected")
    func dotDotEscapeIsRejected() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: (any Error).self) {
            _ = try makeCodebase(at: dir).resolvedFileURL(relativePath: "../../etc/passwd")
        }
    }

    @Test("An absolute path is rejected")
    func absolutePathIsRejected() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: (any Error).self) {
            _ = try makeCodebase(at: dir).resolvedFileURL(relativePath: "/etc/passwd")
        }
    }

    @Test("A symlink that escapes the codebase root is rejected")
    func symlinkEscapeIsRejected() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outside = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("escape"), withDestinationURL: outside)

        #expect(throws: (any Error).self) {
            _ = try makeCodebase(at: dir).resolvedFileURL(relativePath: "escape/secret.txt")
        }
    }

    @Test("A path that validly resolves but doesn't exist on disk is rejected with a specific error")
    func missingFileIsRejected() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: Codebase.SourceResolutionFailure.self) {
            _ = try makeCodebase(at: dir).resolvedFileURL(relativePath: "DoesNotExist.swift")
        }
    }
}
