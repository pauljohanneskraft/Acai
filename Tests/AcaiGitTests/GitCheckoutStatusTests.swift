import Foundation
import Testing
@testable import AcaiGit

@Suite("GitCheckout.hasUncommittedChanges")
struct GitCheckoutStatusTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A freshly checked out repository is clean")
    func freshCheckoutIsClean() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appendingPathComponent("repo", isDirectory: true)
        try GitFixture(directory: directory).make()

        #expect(try GitCheckout(directory: directory).hasUncommittedChanges == false)
    }

    @Test("An edit to a tracked file is dirty")
    func modifiedTrackedFileIsDirty() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appendingPathComponent("repo", isDirectory: true)
        try GitFixture(directory: directory).make()
        try "changed".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        #expect(try GitCheckout(directory: directory).hasUncommittedChanges == true)
    }

    @Test("A new untracked file is dirty")
    func untrackedFileIsDirty() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appendingPathComponent("repo", isDirectory: true)
        try GitFixture(directory: directory).make()
        try "new".write(to: directory.appendingPathComponent("New.swift"), atomically: true, encoding: .utf8)

        #expect(try GitCheckout(directory: directory).hasUncommittedChanges == true)
    }
}
