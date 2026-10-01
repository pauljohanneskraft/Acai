import Foundation
import Testing
@testable import AcaiCore

/// Expanding a build manifest's directory pattern against the filesystem — the shape `packages/*`
/// workspace globs and their `**` variants take.
@Suite("DirectoryGlob", .timeLimit(.minutes(1)))
struct DirectoryGlobTests {

    private func withTree(_ directories: [String], _ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("directory-glob-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in directories {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        try body(root.standardizedFileURL)
    }

    private func matches(_ pattern: String, in root: URL, excluding: Set<String> = []) -> [String] {
        DirectoryGlob(pattern, excludingDirectories: excluding)
            .directories(in: root)
            .map { String($0.path.dropFirst(root.path.count + 1)) }
            .sorted()
    }

    @Test func aPatternWithoutWildcardsResolvesToItself() throws {
        try withTree(["tools/cli"]) { root in
            #expect(matches("tools/cli", in: root) == ["tools/cli"])
            #expect(matches("./tools/cli", in: root) == ["tools/cli"])
            #expect(matches("tools/missing", in: root).isEmpty)
        }
    }

    @Test func aStarMatchesWithinOneComponentOnly() throws {
        try withTree(["packages/core", "packages/ui", "packages/nested/deep", "other/thing"]) { root in
            #expect(matches("packages/*", in: root) == ["packages/core", "packages/nested", "packages/ui"])
            #expect(matches("packages/*/deep", in: root) == ["packages/nested/deep"])
        }
    }

    @Test func aPartialWildcardMatchesOnName() throws {
        try withTree(["libs/app-core", "libs/app-ui", "libs/tools"]) { root in
            #expect(matches("libs/*-core", in: root) == ["libs/app-core"])
            #expect(matches("libs/app-??", in: root) == ["libs/app-ui"])
        }
    }

    /// `**` spans any number of components, including none — so the pattern's own root matches too.
    @Test func aDoubleStarSpansAnyDepth() throws {
        try withTree(["apps/a", "apps/b/c"]) { root in
            #expect(matches("apps/**", in: root) == ["apps", "apps/a", "apps/b", "apps/b/c"])
        }
    }

    @Test func anExcludedDirectoryIsNeverWalked() throws {
        try withTree(["packages/core", "node_modules/dep/packages/vendored"]) { root in
            #expect(matches("**/packages/*", in: root, excluding: ["node_modules"]) == ["packages/core"])
            #expect(matches("**/packages/*", in: root).contains("node_modules/dep/packages/vendored"))
        }
    }

    @Test func filesAreNotDirectories() throws {
        try withTree(["packages/core"]) { root in
            try "x".write(to: root.appendingPathComponent("packages/notes.md"), atomically: true, encoding: .utf8)
            #expect(matches("packages/*", in: root) == ["packages/core"])
        }
    }

    /// A link pointing at one of its own ancestors would make `**` unbounded, so links are not followed.
    @Test func symlinkedDirectoriesAreNotDescendedInto() throws {
        try withTree(["packages/core"]) { root in
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("packages/loop"),
                withDestinationURL: root)
            #expect(matches("packages/*", in: root) == ["packages/core"])
            #expect(matches("**", in: root) == ["", "packages", "packages/core"])
        }
    }
}
