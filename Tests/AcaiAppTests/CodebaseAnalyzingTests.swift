import AcaiCore
import Foundation
import Testing
@testable import AcaiApp

@Suite("CodebaseAnalyzing", .timeLimit(.minutes(1)))
struct CodebaseAnalyzingTests {
    private func makeArtifact() -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Widget.swift"]))
    }

    @Test("FixtureCodebaseAnalyzer decodes the artifact at its URL, ignoring url/fileFilter")
    func decodesArtifact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = makeArtifact()
        let artifactURL = root.appendingPathComponent("artifact.json")
        try JSONEncoder().encode(artifact).write(to: artifactURL)

        let analyzer = FixtureCodebaseAnalyzer(artifactURL: artifactURL)
        let decoded = try await analyzer.enrichedArtifact(at: root.appendingPathComponent("ignored"), fileFilter: nil)
        #expect(decoded == artifact)
    }

    @Test("FixtureCodebaseAnalyzer throws a descriptive error for missing/undecodable content")
    func throwsForMissingArtifact() async {
        let analyzer = FixtureCodebaseAnalyzer(artifactURL: URL(fileURLWithPath: "/does/not/exist.json"))
        await #expect(throws: (any Error).self) {
            try await analyzer.enrichedArtifact(at: URL(fileURLWithPath: "/ignored"), fileFilter: nil)
        }
    }

    @Test func aCodebaseWithItsOwnCannedArtifactGetsItOverTheDefault() {
        let codebaseID = UUID()
        let resolver = CodebaseAnalyzingResolver(fixtures: UITestFixtureResolver(environment: [
            UITestFixtureResolver.fixtureBaseDirVariable: "/fixture",
            UITestFixtureResolver.codebaseArtifactsVariable: "\(codebaseID.uuidString)\t/own.json",
            UITestFixtureResolver.defaultCodebaseArtifactVariable: "/default.json"
        ]))

        #expect(cannedPath(resolver.analyzer(for: codebaseID)) == "/own.json")
        #expect(cannedPath(resolver.analyzer(for: UUID())) == "/default.json")
    }

    @Test func withoutAFixtureEveryCodebaseParsesForReal() {
        let resolver = CodebaseAnalyzingResolver(fixtures: UITestFixtureResolver(environment: [
            UITestFixtureResolver.defaultCodebaseArtifactVariable: "/default.json"
        ]))

        #expect(resolver.analyzer(for: UUID()) is CodebaseAnalyzer)
    }

    @Test func aFixtureWithoutAnyCannedArtifactStillParsesForReal() {
        let resolver = CodebaseAnalyzingResolver(fixtures: UITestFixtureResolver(environment: [
            UITestFixtureResolver.fixtureBaseDirVariable: "/fixture"
        ]))

        #expect(resolver.analyzer(for: UUID()) is CodebaseAnalyzer)
    }

    @Test func onlyAStagedRefGetsACannedComparison() {
        let codebaseID = UUID()
        let resolver = ComparisonArtifactResolver(fixtures: UITestFixtureResolver(environment: [
            UITestFixtureResolver.fixtureBaseDirVariable: "/fixture",
            UITestFixtureResolver.comparisonArtifactsVariable: "\(codebaseID.uuidString)\tHEAD\t/head.json"
        ]))
        let directory = URL(fileURLWithPath: "/repo")

        let staged = resolver.provider(codebaseID: codebaseID, ref: "HEAD", directory: directory)
        #expect((staged as? FixtureComparisonArtifact)?.artifactURL.path == "/head.json")
        #expect(resolver.provider(codebaseID: codebaseID, ref: "main", directory: directory) is GitRevisionSnapshot)
    }

    private func cannedPath(_ analyzer: CodebaseAnalyzing) -> String? {
        (analyzer as? FixtureCodebaseAnalyzer)?.artifactURL.path
    }
}
