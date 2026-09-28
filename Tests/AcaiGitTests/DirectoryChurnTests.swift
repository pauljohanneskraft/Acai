import Foundation
import Testing
@testable import AcaiGit

@Suite("DirectoryChurn")
struct DirectoryChurnTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A working directory's own churn is keyed by repository-root-relative path")
    func churnAtTheRepositoryRoot() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        let resolved = try DirectoryChurn(directory: source).byFile(ref: "main", limit: 10)
        let churn = try #require(resolved)

        // The root commit contributes no touches — see `GitChurn`'s doc comment.
        #expect(churn["README.md"] == 2)
        #expect(churn["Other.swift"] == 1)
    }

    @Test("A subdirectory's churn is offset down to subdirectory-relative paths")
    func churnBelowTheRepositoryRoot() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let resolved = try DirectoryChurn(directory: source.appendingPathComponent("Sub", isDirectory: true))
            .byFile(ref: "main", limit: 10)

        #expect(resolved == ["Nested.swift": 1])
    }

    @Test("A directory outside any repository has no churn at all, rather than an empty map")
    func nonRepositoryDirectoryYieldsNil() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try DirectoryChurn(directory: root).byFile() == nil)
    }

    @Test("A shallow clone refuses rather than counting only the commits it happens to hold")
    func shallowCloneThrows() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()
        let shallow = root.appendingPathComponent("shallow", isDirectory: true)
        try GitFixture(directory: shallow).makeShallowClone(of: source)

        #expect(throws: HistoryNotFetched.self) {
            try DirectoryChurn(directory: shallow).byFile(ref: "main", limit: 10)
        }
    }
}

@Suite("RepositorySubpath")
struct RepositorySubpathTests {
    @Test("An empty prefix passes every entry through unchanged")
    func emptyPrefixPassesThrough() {
        let raw = ["README.md": 2, "Sub/Nested.swift": 1]
        #expect(RepositorySubpath(prefix: "").offsetting(raw) == raw)
    }

    @Test("A prefix strips itself off matching keys and drops the rest")
    func prefixStripsAndFilters() {
        let offset = RepositorySubpath(prefix: "Sub").offsetting(["README.md": 2, "Sub/Nested.swift": 1])
        #expect(offset == ["Nested.swift": 1])
    }

    @Test("A trailing slash in the prefix is tolerated")
    func trailingSlashTolerated() {
        let offset = RepositorySubpath(prefix: "Sub/").offsetting(["Sub/Nested.swift": 1])
        #expect(offset == ["Nested.swift": 1])
    }

    @Test("A directory that is the repository root has an empty prefix")
    func rootDirectoryHasEmptyPrefix() {
        let root = URL(fileURLWithPath: "/tmp/repo")
        #expect(RepositorySubpath(root: root, directory: root).prefix == "")
    }

    @Test("A directory below the root carries its relative path as the prefix")
    func nestedDirectoryCarriesRelativePath() {
        let root = URL(fileURLWithPath: "/tmp/repo")
        let nested = URL(fileURLWithPath: "/tmp/repo/Sub/Package")
        #expect(RepositorySubpath(root: root, directory: nested).prefix == "Sub/Package")
    }

    @Test("A directory outside the root falls back to an empty prefix")
    func unrelatedDirectoryFallsBackToEmptyPrefix() {
        let root = URL(fileURLWithPath: "/tmp/repo")
        let elsewhere = URL(fileURLWithPath: "/tmp/other")
        #expect(RepositorySubpath(root: root, directory: elsewhere).prefix == "")
    }
}
