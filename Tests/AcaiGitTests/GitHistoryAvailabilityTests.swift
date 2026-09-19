import Foundation
import Testing
@testable import AcaiGit

@Suite("GitHistoryAvailability")
struct GitHistoryAvailabilityTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeShallowClone(root: URL) throws -> URL {
        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()
        let shallow = root.appendingPathComponent("shallow", isDirectory: true)
        try GitFixture(directory: shallow).makeShallowClone(of: source)
        return shallow
    }

    @Test("A full clone is not shallow")
    func fullCloneIsNotShallow() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        #expect(!GitHistoryAvailability(directory: source).isShallow)
    }

    @Test("A depth-1 clone is shallow, including from a subdirectory")
    func shallowCloneIsShallow() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shallow = try makeShallowClone(root: root)

        #expect(GitHistoryAvailability(directory: shallow).isShallow)
        #expect(GitHistoryAvailability(directory: shallow.appendingPathComponent("Sub")).isShallow)
    }

    @Test("A linked worktree of a shallow clone reports it as shallow")
    func worktreeOfShallowCloneIsShallow() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shallow = try makeShallowClone(root: root)
        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        try GitWorktree(repositoryDirectory: shallow).add(name: "worktree", at: worktree)

        #expect(GitHistoryAvailability(directory: worktree).isShallow)
    }

    @Test("History-walking operations refuse a shallow clone instead of answering from a truncated history")
    func historyOperationsRefuseShallowClone() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shallow = try makeShallowClone(root: root)

        #expect(throws: HistoryNotFetched.self) { try GitChurn(directory: shallow).byFile(ref: "HEAD") }
        #expect(throws: HistoryNotFetched.self) { try GitCheckout(directory: shallow).mergeBase("main", "feature") }
        #expect(throws: HistoryNotFetched.self) {
            try GitDiffSnapshot(directory: shallow, reference: "HEAD~1").extractedDirectory()
        }
    }

    @Test("A shallow clone still extracts a branch tip")
    func shallowCloneExtractsBranchTip() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shallow = try makeShallowClone(root: root)

        let extracted = try GitDiffSnapshot(directory: shallow, reference: "feature").extractedDirectory()
        defer { try? FileManager.default.removeItem(at: extracted) }
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("Feature.swift").path))
    }
}
