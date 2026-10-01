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

        let resolved = try #require(
            try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["README.md": [1...1]], source: .revision("HEAD")))
        let line = try #require(resolved["README.md"]?[1...1])

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
            try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["README.md": [1...1], "Other.swift": [1...1]], source: .workingTree))

        #expect(Set(resolved.keys) == ["README.md", "Other.swift"])
        #expect(resolved["Other.swift"]?[1...1]?.authorName == "Test")
    }

    @Test("A subdirectory's own paths are answered, without naming the repository root")
    func blameBelowTheRepositoryRoot() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let resolved = try #require(
            try DirectoryBlame(directory: source.appendingPathComponent("Sub", isDirectory: true))
                .lastTouched(inRangesByFile: ["Nested.swift": [1...1]], source: .workingTree))

        #expect(resolved["Nested.swift"]?[1...1]?.authorName == "Test")
    }

    @Test("A ref other than HEAD is blamed as of that revision, not the checked-out one")
    func blameAtAnotherRef() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // `make()` leaves the working tree on `main`; `Feature.swift` exists only on `feature`.
        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()
        let blame = DirectoryBlame(directory: source)

        let onMain = try #require(
            try blame.lastTouched(inRangesByFile: ["Feature.swift": [1...1]], source: .revision("main")))
        #expect(onMain["Feature.swift"] == nil)

        let onFeature = try #require(
            try blame.lastTouched(inRangesByFile: ["Feature.swift": [1...1]], source: .revision("feature")))
        #expect(onFeature["Feature.swift"]?[1...1]?.authorName == "Test")
    }

    @Test("A range past the end of the file is absent, and one running past it is cut at the end")
    func rangeBeyondTheFile() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithLayeredEdits()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["Layered.swift": [10...12, 3...99]], source: .revision("HEAD")))

        #expect(resolved["Layered.swift"]?[10...12] == nil)
        #expect(resolved["Layered.swift"]?[3...99]?.changedAt == GitFixture.layeredCommitDate)
    }

    @Test("A range reports the most recent change anywhere inside it, not only on its first line")
    func rangeReportsItsMostRecentChange() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithLayeredEdits()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["Layered.swift": [1...2, 1...4]], source: .revision("HEAD")))

        #expect(resolved["Layered.swift"]?[1...2]?.changedAt == GitFixture.layeredOriginalDate)
        #expect(resolved["Layered.swift"]?[1...4]?.changedAt == GitFixture.layeredCommitDate)
    }

    @Test("A line's age is when its change was committed, not when it was first authored")
    func ageIsTheCommitterDate() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithLayeredEdits()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["Layered.swift": [3...3]], source: .revision("HEAD")))

        #expect(resolved["Layered.swift"]?[3...3]?.changedAt == GitFixture.layeredCommitDate)
    }

    @Test("Authors are named as the repository's mailmap canonicalises them")
    func authorsFollowTheMailmap() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithLayeredEdits()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["Layered.swift": [1...1]], source: .workingTree))

        #expect(resolved["Layered.swift"]?[1...1]?.authorName == "Canonical Test")
    }

    @Test("Uncommitted edits shift the working tree's lines without moving their authorship")
    func workingTreeEditsKeepTheirLinesAttributed() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithLayeredEdits()
        try "inserted\na\nb\nC\nd\n".write(
            to: source.appendingPathComponent("Layered.swift"), atomically: true, encoding: .utf8)
        let blame = DirectoryBlame(directory: source)

        let workingTree = try #require(
            try blame.lastTouched(inRangesByFile: ["Layered.swift": [1...1, 2...2, 4...4]], source: .workingTree))
        #expect(workingTree["Layered.swift"]?[1...1] == nil)
        #expect(workingTree["Layered.swift"]?[2...2]?.changedAt == GitFixture.layeredOriginalDate)
        #expect(workingTree["Layered.swift"]?[4...4]?.changedAt == GitFixture.layeredCommitDate)

        let atHead = try #require(
            try blame.lastTouched(inRangesByFile: ["Layered.swift": [1...1]], source: .revision("HEAD")))
        #expect(atHead["Layered.swift"]?[1...1]?.changedAt == GitFixture.layeredOriginalDate)
    }

    @Test("A cancelled caller stops the walk rather than blaming every remaining file")
    func cancellationStopsTheWalk() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["README.md": [1...1]], source: .workingTree)
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("A file git doesn't know drops out without costing the files it does")
    func untrackedFileDoesNotFailTheRest() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        let resolved = try #require(
            try DirectoryBlame(directory: source).lastTouched(
                inRangesByFile: ["README.md": [1...1], "Missing.swift": [1...1]], source: .workingTree))

        #expect(resolved["Missing.swift"] == nil)
        #expect(resolved["README.md"]?[1...1] != nil)
    }

    @Test("Asking about nothing reads no history at all")
    func emptyRequestIsEmpty() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).makeWithRepeatedTouches()

        #expect(
            try DirectoryBlame(directory: source)
                .lastTouched(inRangesByFile: ["README.md": []], source: .workingTree)?.isEmpty == true)
    }

    @Test("A directory outside any repository has no authorship at all, rather than an empty map")
    func nonRepositoryDirectoryYieldsNil() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            try DirectoryBlame(directory: root)
                .lastTouched(inRangesByFile: ["README.md": [1...1]], source: .workingTree) == nil)
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
            try DirectoryBlame(directory: shallow)
                .lastTouched(inRangesByFile: ["README.md": [1...1]], source: .workingTree)
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
