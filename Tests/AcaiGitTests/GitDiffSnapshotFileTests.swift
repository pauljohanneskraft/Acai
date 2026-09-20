import Foundation
import Testing
@testable import AcaiGit

@Suite("GitDiffSnapshot single file")
struct GitDiffSnapshotFileTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Reads a file as it was at a revision, not as it is in the working tree")
    func readsFileAtRevision() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try GitFixture(directory: root).make()
        try "edited".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let file = try GitDiffSnapshot(directory: root, reference: "v1").extractedFile(relativePath: "README.md")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(file.lastPathComponent == "README.md")
        #expect(try String(contentsOf: file, encoding: .utf8) == "hello")
    }

    @Test("Resolves paths relative to a subdirectory")
    func readsFileRelativeToSubdirectory() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try GitFixture(directory: root).make()

        let file = try GitDiffSnapshot(directory: root.appendingPathComponent("Sub"), reference: "main")
            .extractedFile(relativePath: "Nested.swift")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(try String(contentsOf: file, encoding: .utf8) == "world")
    }

    @Test("A file missing at the revision, or a path climbing out of the subtree, is refused")
    func refusesMissingOrEscapingPath() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try GitFixture(directory: root).make()

        #expect(throws: GitDiffSnapshot.Failure.self) {
            try GitDiffSnapshot(directory: root, reference: "main").extractedFile(relativePath: "Feature.swift")
        }
        #expect(throws: GitDiffSnapshot.Failure.self) {
            try GitDiffSnapshot(directory: root.appendingPathComponent("Sub"), reference: "main")
                .extractedFile(relativePath: "../README.md")
        }
    }

    @Test("commitSHA names the commit the revision resolves to")
    func commitSHAResolvesRevision() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let commits = try GitFixture(directory: root).make()

        #expect(try GitDiffSnapshot(directory: root, reference: "v1").commitSHA() == commits.tagged)
        #expect(try GitDiffSnapshot(directory: root, reference: "feature").commitSHA() == commits.feature)
    }

    @Test("Extraction stops when its task is cancelled")
    func extractionObservesCancellation() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try GitFixture(directory: root).make()

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try GitDiffSnapshot(directory: root, reference: "main").extractedDirectory()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
