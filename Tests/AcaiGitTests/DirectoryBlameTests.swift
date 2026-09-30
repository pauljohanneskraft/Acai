import Foundation
import Testing
@testable import AcaiGit

@Suite("DirectoryBlame")
struct DirectoryBlameTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A tracked line carries the author of the commit that last changed it")
    func blameAtTheRepositoryRoot() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        let resolved = try DirectoryBlame(directory: source).lines(byFile: ["README.md": [1]])
        let line = try #require(try #require(resolved)["README.md"]?[1])

        #expect(line.authorName == "Test")
        #expect(line.changedAt.timeIntervalSince1970 > 0)
    }

    @Test("Several files are answered in one call, each keyed as it was asked for")
    func blameAcrossSeveralFiles() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lines(byFile: ["README.md": [1], "Other.swift": [1]]))

        #expect(Set(resolved.keys) == ["README.md", "Other.swift"])
        #expect(resolved["Other.swift"]?[1]?.authorName == "Test")
    }

    @Test("A subdirectory's own paths are answered, without naming the repository root")
    func blameBelowTheRepositoryRoot() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let resolved = try #require(
            try DirectoryBlame(directory: source.appendingPathComponent("Sub", isDirectory: true))
                .lines(byFile: ["Nested.swift": [1]]))

        #expect(resolved["Nested.swift"]?[1]?.authorName == "Test")
    }

    @Test("A line past the end of the file is absent rather than attributed to the last one")
    func lineBeyondTheFileIsAbsent() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lines(byFile: ["README.md": [1, 99]]))

        #expect(resolved["README.md"]?[99] == nil)
        #expect(resolved["README.md"]?[1] != nil)
    }

    @Test("A file git doesn't know drops out without costing the files it does")
    func untrackedFileDoesNotFailTheRest() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lines(byFile: ["README.md": [1], "Missing.swift": [1]]))

        #expect(resolved["Missing.swift"] == nil)
        #expect(resolved["README.md"]?[1] != nil)
    }

    @Test("Asking about nothing reads no history at all")
    func emptyRequestIsEmpty() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        #expect(try DirectoryBlame(directory: source).lines(byFile: ["README.md": []])?.isEmpty == true)
    }

    @Test("A directory outside any repository has no authorship at all, rather than an empty map")
    func nonRepositoryDirectoryYieldsNil() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try DirectoryBlame(directory: root).lines(byFile: ["README.md": [1]]) == nil)
    }

    @Test("A shallow clone refuses rather than charging every older line to the graft")
    func shallowCloneThrows() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()
        let shallow = root.appendingPathComponent("shallow", isDirectory: true)
        try GitFixture(directory: shallow).makeShallowClone(of: source)

        #expect(throws: HistoryNotFetched.self) {
            try DirectoryBlame(directory: shallow).lines(byFile: ["README.md": [1]])
        }
    }
}

@Suite("RepositorySubpath prefixing")
struct RepositorySubpathPrefixingTests {
    @Test("An empty prefix passes every entry through unchanged")
    func emptyPrefixPassesThrough() {
        let raw = ["README.md": Set([1]), "Sub/Nested.swift": Set([2])]
        #expect(RepositorySubpath(prefix: "").prefixing(raw) == raw)
    }

    @Test("A prefix names every key the way the repository does")
    func prefixNamesKeysAsTheRepositoryDoes() {
        #expect(
            RepositorySubpath(prefix: "Sub").prefixing(["Nested.swift": Set([1])])
                == ["Sub/Nested.swift": Set([1])])
    }

    @Test("A trailing slash in the prefix is tolerated")
    func trailingSlashTolerated() {
        #expect(
            RepositorySubpath(prefix: "Sub/").prefixing(["Nested.swift": Set([1])])
                == ["Sub/Nested.swift": Set([1])])
    }

    @Test("Prefixing and offsetting are inverses of each other")
    func prefixingRoundTripsThroughOffsetting() {
        let subpath = RepositorySubpath(prefix: "Sub/Package")
        let raw = ["Sources/A.swift": Set([1, 2]), "Sources/B.swift": Set([3])]
        #expect(subpath.offsetting(subpath.prefixing(raw)) == raw)
    }
}
