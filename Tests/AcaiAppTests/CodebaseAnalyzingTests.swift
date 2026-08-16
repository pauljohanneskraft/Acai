import AcaiCore
import Foundation
import Testing
@testable import AcaiApp

@Suite("CodebaseAnalyzing")
struct CodebaseAnalyzingTests {
    private func makeArtifact() -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Widget.swift"]))
    }

    @Test("FixtureCodebaseAnalyzer decodes the artifact at its URL, ignoring url/fileFilter")
    func decodesArtifact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = makeArtifact()
        let artifactURL = root.appendingPathComponent("artifact.json")
        try JSONEncoder().encode(artifact).write(to: artifactURL)

        let analyzer = FixtureCodebaseAnalyzer(artifactURL: artifactURL)
        let decoded = try analyzer.enrichedArtifact(at: root.appendingPathComponent("ignored"), fileFilter: nil)
        #expect(decoded == artifact)
    }

    @Test("FixtureCodebaseAnalyzer throws a descriptive error for missing/undecodable content")
    func throwsForMissingArtifact() {
        let analyzer = FixtureCodebaseAnalyzer(artifactURL: URL(fileURLWithPath: "/does/not/exist.json"))
        #expect(throws: (any Error).self) {
            try analyzer.enrichedArtifact(at: URL(fileURLWithPath: "/ignored"), fileFilter: nil)
        }
    }
}
