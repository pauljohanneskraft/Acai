import Foundation
import Testing
@testable import AcaiApp

@Suite("Codebase repository reference persistence")
struct CodebaseRepositoryReferenceTests {
    @Test func decodingLegacyJSONWithoutRepositoryDefaultsToNil() throws {
        // Real pre-B02 shape: no "repository" key at all.
        let legacyJSON = Data("""
        {
            "id": "8C7E6B2B-8B8B-4B8B-8B8B-8B8B8B8B8B8B",
            "name": "MyLibrary",
            "directoryPath": "/Users/me/Code/MyLibrary",
            "hasArtifact": false,
            "hasParseErrors": false,
            "parseDiagnosticCount": 0
        }
        """.utf8)

        let codebase = try JSONDecoder().decode(Codebase.self, from: legacyJSON)

        #expect(codebase.repository == nil)
        #expect(codebase.directoryPath == "/Users/me/Code/MyLibrary")
    }

    @Test func roundTripsRepositoryReferenceThroughEncodeAndDecode() throws {
        var codebase = Codebase(name: "MyLibrary", directoryPath: "/Users/me/Code/MyLibrary")
        codebase.repository = CodebaseRepositoryReference(
            remoteURL: URL(string: "https://github.com/owner/repo.git")!, ref: "main", subpath: "packages/core")

        let data = try JSONEncoder().encode(codebase)
        let decoded = try JSONDecoder().decode(Codebase.self, from: data)

        #expect(decoded.repository == codebase.repository)
        #expect(decoded.repository?.ref == "main")
        #expect(decoded.repository?.subpath == "packages/core")
    }
}

@Suite("Codebase.resolvedFileURL path-escape validation")
struct CodebaseResolvedFileURLTests {
    private func makeCodebase(in directory: URL) -> Codebase {
        Codebase(name: "Fixture", directoryPath: directory.path)
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func resolvesAPlainRelativePathInsideTheCodebase() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codebase = makeCodebase(in: root)

        let resolved = try codebase.resolvedFileURL(relativePath: "Sources/Foo.swift")

        #expect(resolved.path == root.appendingPathComponent("Sources/Foo.swift").resolvingSymlinksInPath().path)
    }

    @Test func rejectsAnAbsolutePath() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codebase = makeCodebase(in: root)

        #expect(throws: Codebase.ResolvedFileURLFailure.self) {
            try codebase.resolvedFileURL(relativePath: "/etc/passwd")
        }
    }

    @Test func rejectsADotDotEscapingPath() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let codebase = makeCodebase(in: root)

        #expect(throws: Codebase.ResolvedFileURLFailure.self) {
            try codebase.resolvedFileURL(relativePath: "../../../etc/passwd")
        }
    }

    @Test func rejectsASymlinkThatEscapesTheCodebaseRoot() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // A directory outside `root` that the symlink points at.
        let outside = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"), withDestinationURL: outside)

        let codebase = makeCodebase(in: root)

        #expect(throws: Codebase.ResolvedFileURLFailure.self) {
            try codebase.resolvedFileURL(relativePath: "escape/secret.txt")
        }
    }
}
