import Foundation
import Testing
@testable import AcaiApp

/// Path-escape/symlink-escape validation for `PathEscapeGuard`, the fresh implementation backing
/// `Codebase.resolvedFileURL(relativePath:)` (`BACKLOG.md` B30). Required by
/// `USABILITY_GUARDRAILS.md` §5: any path resolved from external input (a parsed `SourceLocation`,
/// ultimately traceable to a GitHub-sourced codebase's tree) must be validated before use.
@Suite("PathEscapeGuard")
struct PathEscapeGuardTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathEscapeGuardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A valid relative path resolves inside the root")
    func validRelativePathResolves() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "class Foo {}\n".write(
            to: sub.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)

        let resolved = try PathEscapeGuard(root: root).resolvedURL(forRelativePath: "Sources/Foo.swift")

        #expect(resolved.path == sub.appendingPathComponent("Foo.swift").resolvingSymlinksInPath().path)
    }

    @Test("A '../'-escaping relative path is rejected")
    func dotDotEscapeIsRejected() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: PathEscapeGuard.Failure.self) {
            _ = try PathEscapeGuard(root: root).resolvedURL(forRelativePath: "../../etc/passwd")
        }
    }

    @Test("An absolute path is rejected, even one that stays under the root as a string")
    func absolutePathIsRejected() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Deliberately chosen so a naive join-then-prefix-check would wrongly accept it: appending
        // an absolute path to a URL does not replace the base, so "root + /etc/passwd" never
        // escapes root as a string comparison — it must still be rejected because it was given as
        // an absolute path in the first place.
        #expect(throws: PathEscapeGuard.Failure.self) {
            _ = try PathEscapeGuard(root: root).resolvedURL(forRelativePath: "/etc/passwd")
        }
    }

    @Test("A relative path through a symlink that escapes the root is rejected")
    func symlinkEscapeIsRejected() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try "secret".write(
            to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)

        // "root/escape" is a symlink pointing at a directory entirely outside root.
        let symlink = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        #expect(throws: PathEscapeGuard.Failure.self) {
            _ = try PathEscapeGuard(root: root).resolvedURL(forRelativePath: "escape/secret.txt")
        }
    }

    @Test("A relative path that merely shares the root's path as a string prefix is rejected")
    func siblingDirectorySharingStringPrefixIsRejected() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // A sibling directory whose name has `root`'s full path as a *string* prefix (root name +
        // suffix) but is not actually nested inside it — a plain `hasPrefix` check on `.path` would
        // wrongly accept a path resolving into this directory.
        let sibling = URL(fileURLWithPath: root.path + "-evil", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try "class Evil {}\n".write(
            to: sibling.appendingPathComponent("Evil.swift"), atomically: true, encoding: .utf8)

        let escapingPath = "../\(root.lastPathComponent)-evil/Evil.swift"
        #expect(throws: PathEscapeGuard.Failure.self) {
            _ = try PathEscapeGuard(root: root).resolvedURL(forRelativePath: escapingPath)
        }
    }
}
