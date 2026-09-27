import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// The journeys' canned artifacts stand in for a real parse, so every canned journey is only as
/// honest as these files. Nothing regenerates them automatically (`FixtureArtifactGeneratorTests`
/// runs in record mode only), so this pins them against what the parser produces today: when it
/// fails, re-record with `ACAI_RECORD_FIXTURE_ARTIFACTS=1 swift test --filter FixtureArtifactGenerator`.
@Suite("Seeded fixture contract")
struct SeededFixtureContractTests {
    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/AcaiUITests/Fixtures/seeded")
    }

    @Test func theCannedArtifactMatchesARealParseOfTheSamplePackage() throws {
        let parsed = try CodebaseAnalyzer().enrichedArtifact(
            at: fixturesDirectory.appendingPathComponent("SampleSwiftPackage"))

        #expect(try canned("seeded.json") == parsed, "The canned seeded artifact no longer matches a real parse")
    }

    /// `CompareGitRevisionTests` compares these two as HEAD against the working tree, so the delta it
    /// asserts exists only as long as they differ by exactly the added type.
    @Test func theComparisonPairDiffersOnlyByTheAddedType() throws {
        let head = try canned("comparison-HEAD.json")
        let withAdded = try canned("seeded-with-added.json")

        #expect(head == (try canned("seeded.json")))
        #expect(Set(withAdded.types.map(\.name)).subtracting(head.types.map(\.name)) == ["Added"])
        #expect(Set(head.types.map(\.name)).subtracting(withAdded.types.map(\.name)).isEmpty)
    }

    private func canned(_ filename: String) throws -> CodeArtifact {
        let url = fixturesDirectory.appendingPathComponent("artifacts").appendingPathComponent(filename)
        return try JSONDecoder().decode(CodeArtifact.self, from: try Data(contentsOf: url))
    }
}
