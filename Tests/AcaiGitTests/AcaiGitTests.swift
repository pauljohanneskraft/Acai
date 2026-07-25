import Foundation
import SwiftGitX
import Testing
@testable import AcaiGit

@Suite("AcaiGit", .serialized)
struct AcaiGitTests {
    /// A fresh scratch directory per test, removed afterward.
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Clones a local repository at a branch and returns its head SHA")
    func clonesAtBranch() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let commits = try GitFixture(directory: source).make()

        let destination = root.appendingPathComponent("clone", isDirectory: true)
        let sha = try await GitClone(remoteURL: source, ref: "main").sync(into: destination)

        #expect(sha == commits.tagged)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.md").path))
    }

    @Test("Clones at a tag")
    func clonesAtTag() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let commits = try GitFixture(directory: source).make()

        let destination = root.appendingPathComponent("clone", isDirectory: true)
        let sha = try await GitClone(remoteURL: source, ref: "v1").sync(into: destination)

        #expect(sha == commits.tagged)
    }

    @Test("Re-syncing an existing clone fetches and switches instead of re-cloning")
    func resyncFetchesInPlace() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let commits = try GitFixture(directory: source).make()

        let destination = root.appendingPathComponent("clone", isDirectory: true)
        try await GitClone(remoteURL: source, ref: "main").sync(into: destination)

        let sha = try await GitClone(remoteURL: source, ref: "feature").sync(into: destination)
        #expect(sha == commits.feature)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Feature.swift").path))
    }

    @Test("Lists branch and tag names")
    func listsRefNames() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let destination = root.appendingPathComponent("clone", isDirectory: true)
        try await GitClone(remoteURL: source, ref: "main").sync(into: destination)

        let names = try GitCheckout(directory: destination).refNames()
        #expect(names.contains("main"))
        #expect(names.contains("feature"))
        #expect(names.contains("v1"))
    }

    @Test("Extracts a prior revision's tree without touching the working directory")
    func extractsDiffSnapshot() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let destination = root.appendingPathComponent("clone", isDirectory: true)
        try await GitClone(remoteURL: source, ref: "main").sync(into: destination)

        let extracted = try GitDiffSnapshot(directory: destination, reference: "HEAD~1").extractedDirectory()
        defer { try? FileManager.default.removeItem(at: extracted) }

        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("README.md").path))
        #expect(!FileManager.default.fileExists(atPath: extracted.appendingPathComponent("Sub/Nested.swift").path))
        // The real working directory (at HEAD, the tagged commit) is untouched.
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Sub/Nested.swift").path))
    }

    @Test("Extracting from a subdirectory only extracts that subtree")
    func extractsScopedToSubdirectory() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try GitFixture(directory: source).make()

        let destination = root.appendingPathComponent("clone", isDirectory: true)
        try await GitClone(remoteURL: source, ref: "main").sync(into: destination)

        let subdirectory = destination.appendingPathComponent("Sub", isDirectory: true)
        let extracted = try GitDiffSnapshot(directory: subdirectory, reference: "HEAD").extractedDirectory()
        defer { try? FileManager.default.removeItem(at: extracted) }

        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("Nested.swift").path))
        #expect(!FileManager.default.fileExists(atPath: extracted.appendingPathComponent("README.md").path))
    }

    @Test("Resolves HEAD~N and branch/tag names via GitReference")
    func resolvesReferences() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let commits = try GitFixture(directory: source).make()

        let destination = root.appendingPathComponent("clone", isDirectory: true)
        try await GitClone(remoteURL: source, ref: "main").sync(into: destination)

        let repository = try Repository(at: destination, createIfNotExists: false)
        #expect(try GitReference(name: "HEAD~1").resolve(in: repository).id.hex == commits.initial)
        #expect(try GitReference(name: "v1").resolve(in: repository).id.hex == commits.tagged)
    }
}
