import Testing
import Foundation
@testable import AcaiCore

@Suite("Metadata Codable Round Trip Tests")
struct MetadataRoundTripTests {

    /// Every `Metadata` field set to a non-default value, so a field added without a matching
    /// `Codable` member fails here instead of silently not persisting.
    @Test func fullyPopulatedMetadata() throws {
        let original = CodeArtifact.Metadata(
            sourceLanguage: .swift,
            filePaths: ["Sources/A/A.swift", "Sources/B/B.swift"],
            toolVersion: "1.2.3",
            parseDiagnostics: [
                ParseDiagnostic(
                    location: SourceLocation(filePath: "Sources/A/A.swift", line: 3, column: 7),
                    kind: .missing,
                    message: "expected '}'"
                )
            ],
            discoveredRoots: [
                CodeArtifact.DiscoveredRoot(
                    path: ".",
                    detector: "SwiftPackageManagerDetector",
                    languages: [.swift]
                ),
                CodeArtifact.DiscoveredRoot(
                    path: "web",
                    detector: "NodeDetector",
                    languages: [.typeScript, .javaScript]
                )
            ]
        )
        #expect(try roundTrip(original) == original)
    }

    /// An empty `discoveredRoots` is written as an empty array rather than omitted, so the key is
    /// always present and a reader never has to distinguish "absent" from "none discovered".
    @Test func emptyDiscoveredRootsStillEncodesTheKey() throws {
        let metadata = CodeArtifact.Metadata(sourceLanguage: .swift, filePaths: ["A.swift"])
        let data = try JSONEncoder().encode(metadata)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["discoveredRoots"] is [Any])
        #expect(try roundTrip(metadata) == metadata)
    }

    /// An artifact written before `discoveredRoots` existed has no such key at all — not an empty
    /// array, an absent one. It must still decode, with `discoveredRoots` reading as `[]`, exactly as
    /// issue #336 requires; a plain synthesized decoder would reject it with `keyNotFound`.
    @Test func metadataWithoutDiscoveredRootsKeyDecodesAsEmpty() throws {
        let legacyJSON = Data("""
        {"sourceLanguage":"swift","filePaths":["A.swift"],"parseDiagnostics":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(CodeArtifact.Metadata.self, from: legacyJSON)
        #expect(decoded.discoveredRoots.isEmpty)
        #expect(decoded.sourceLanguage == .swift)
        #expect(decoded.filePaths == ["A.swift"])
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
