#if os(macOS)
import Foundation
import Testing
@testable import AcaiApp

@Suite("FindingsBlameWalk")
struct FindingsBlameWalkTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func walk(_ codebase: Codebase, ranges: [String: Set<ClosedRange<Int>>], root: URL) -> FindingsBlameWalk {
        FindingsBlameWalk(
            entries: [.init(codebaseID: codebase.id, codebase: codebase, rangesByFile: ranges)],
            gitRepositoriesDir: root.appendingPathComponent("hub", isDirectory: true))
    }

    @Test("A local folder is blamed as its working tree, so an uncommitted line shifts nothing")
    func localFolderIsBlamedAsItsWorkingTree() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try GitTestRepository.make(in: root)
        try "inserted\nhello".write(
            to: repository.directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let codebase = Codebase(name: "Local", directoryPath: repository.directory.path)

        let outcome = try walk(codebase, ranges: ["README.md": [1...1, 2...2]], root: root).run()

        #expect(outcome.lastTouched[FindingBlameRange(codebaseID: codebase.id, path: "README.md", lines: 1...1)] == nil)
        #expect(
            outcome.lastTouched[FindingBlameRange(codebaseID: codebase.id, path: "README.md", lines: 2...2)]?
                .authorName == "Test")
        #expect(outcome.failure == nil)
    }

    @Test("A shallow clone is reported as needing full history rather than silently omitted")
    func shallowCloneIsReported() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try GitTestRepository.make(in: root)
        try repository.commit("README.md", "hello again", message: "second")
        let shallow = root.appendingPathComponent("shallow", isDirectory: true)
        try GitTestRepository(directory: root).git(
            "clone", "-q", "--depth", "1", repository.directory.absoluteURL.absoluteString, shallow.path)
        let codebase = Codebase(name: "Shallow", directoryPath: shallow.path)

        let outcome = try walk(codebase, ranges: ["README.md": [1...1]], root: root).run()

        #expect(outcome.historyNotFetched == [codebase.id])
        #expect(outcome.lastTouched.isEmpty)
        #expect(outcome.failure == nil)
    }

    @Test("A folder outside any repository contributes nothing and is not a failure")
    func noRepositoryIsNotAFailure() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codebase = Codebase(name: "Plain", directoryPath: root.path)

        let outcome = try walk(codebase, ranges: ["README.md": [1...1]], root: root).run()

        #expect(outcome.lastTouched.isEmpty)
        #expect(outcome.historyNotFetched.isEmpty)
        #expect(outcome.failure == nil)
    }

    @Test("A cancelled walk stops instead of blaming the remaining codebases")
    func cancelledWalkStops() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try GitTestRepository.make(in: root)
        let blameWalk = walk(
            Codebase(name: "Local", directoryPath: repository.directory.path),
            ranges: ["README.md": [1...1]], root: root)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try blameWalk.run()
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
#endif
