import Foundation
import Testing
@testable import AcaiApp

@Suite("Codebase repository reference persistence")
struct CodebaseRepositoryReferenceTests {
    @Test func decodingLegacyJSONWithoutRepositoryDefaultsToNil() throws {
        // Real legacy shape, from before this field existed: no "repository" key at all.
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
