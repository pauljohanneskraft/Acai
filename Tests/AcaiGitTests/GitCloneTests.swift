import Foundation
import Testing
@testable import AcaiGit

@Suite("GitClone cancellation")
struct GitCloneTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("An already-cancelled Task aborts a fresh clone with CancellationError instead of running to completion")
    func alreadyCancelledTaskAbortsImmediately() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()
        let destination = root.appendingPathComponent("clone", isDirectory: true)

        let task = Task {
            try await GitClone(remoteURL: source, ref: "main").sync(into: destination)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Cancelling a fresh clone leaves nothing behind at the destination")
    func cancelledCloneLeavesNoPartialDirectory() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()
        let destination = root.appendingPathComponent("clone", isDirectory: true)

        let task = Task {
            try await GitClone(remoteURL: source, ref: "main").sync(into: destination)
        }
        task.cancel()
        _ = try? await task.value

        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
