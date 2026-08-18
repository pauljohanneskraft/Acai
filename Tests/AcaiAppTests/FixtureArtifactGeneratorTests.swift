import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Not run by default (`ACAI_RECORD_FIXTURE_ARTIFACTS` gates it) — regenerates the pre-baked
/// `CodeArtifact` JSON fixtures `CompareGitRevisionTests` and friends decode via
/// `-AcaiUITestCodebaseArtifact`/`-AcaiUITestComparisonArtifact`, instead of driving a real parse
/// through the UI. Re-run this whenever `Fixtures/seeded/SampleSwiftPackage` changes; never hand-edit
/// the generated JSON.
@Suite("Fixture CodeArtifact generation (record mode)")
struct FixtureArtifactGeneratorTests {
    private var sampleSwiftPackageDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/AcaiUITests/Fixtures/seeded/SampleSwiftPackage")
    }

    private var artifactsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/AcaiUITests/Fixtures/seeded/artifacts")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ACAI_RECORD_FIXTURE_ARTIFACTS"] != nil))
    func regenerateSeededFixtureArtifacts() throws {
        try FileManager.default.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)

        // Current on-disk state (Base/Helper/Worker/Derived, no `Added.swift`) is both the plain
        // "reindex the seeded codebase" result most journeys need, and what `CompareGitRevisionTests`
        // commits as `HEAD` before adding `Added.swift`.
        let headArtifact = try CodebaseAnalyzer().enrichedArtifact(at: sampleSwiftPackageDirectory)
        try write(headArtifact, to: "seeded.json")
        try write(headArtifact, to: "comparison-HEAD.json")

        // The working-tree side after the uncommitted `Added.swift` edit.
        let addedFile = sampleSwiftPackageDirectory
            .appendingPathComponent("Sources/SampleSwiftPackage/Added.swift")
        try "public class Added {}\n".write(to: addedFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: addedFile) }
        let currentArtifact = try CodebaseAnalyzer().enrichedArtifact(at: sampleSwiftPackageDirectory)
        try write(currentArtifact, to: "seeded-with-added.json")
    }

    private func write(_ artifact: CodeArtifact, to filename: String) throws {
        let data = try JSONEncoder().encode(artifact)
        try data.write(to: artifactsDirectory.appendingPathComponent(filename))
    }
}
