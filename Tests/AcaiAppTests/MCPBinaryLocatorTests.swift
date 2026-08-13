import Foundation
import Testing
@testable import AcaiApp

@Suite("MCPBinaryLocator")
struct MCPBinaryLocatorTests {
    @Test("Finds an executable binary in the first candidate directory that has one")
    func findsBinaryInFirstMatchingDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let binDir = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let binaryPath = binDir.appendingPathComponent("acai-mcp")
        try makeExecutableFile(at: binaryPath)

        let locator = MCPBinaryLocator(
            candidateDirectories: [binDir.path, root.appendingPathComponent("other").path])

        #expect(locator.installedBinaryPath == binaryPath.path)
    }

    @Test("Prefers an earlier candidate directory over a later one that also has the binary")
    func prefersEarlierDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstDir = root.appendingPathComponent("first")
        let secondDir = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        try makeExecutableFile(at: firstDir.appendingPathComponent("acai-mcp"))
        try makeExecutableFile(at: secondDir.appendingPathComponent("acai-mcp"))

        let locator = MCPBinaryLocator(candidateDirectories: [firstDir.path, secondDir.path])

        #expect(locator.installedBinaryPath == firstDir.appendingPathComponent("acai-mcp").path)
    }

    @Test("Reports nil when no candidate directory has the binary")
    func reportsNilWhenNotInstalled() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let locator = MCPBinaryLocator(candidateDirectories: [root.appendingPathComponent("empty").path])

        #expect(locator.installedBinaryPath == nil)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutableFile(at url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
