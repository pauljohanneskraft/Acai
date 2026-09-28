import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Not run by default (`ACAI_RECORD_FIXTURE_ARTIFACTS` gates it) — regenerates the pre-baked
/// `CodeArtifact` JSON fixtures `CompareGitRevisionTests` and friends decode via
/// `ACAI_UITEST_CODEBASE_ARTIFACTS`/`ACAI_UITEST_COMPARISON_ARTIFACTS`, instead of driving a real parse
/// through the UI. Re-run this whenever `Fixtures/seeded/SampleSwiftPackage` changes; never hand-edit
/// the generated JSON.
@Suite("Fixture CodeArtifact generation (record mode)", .timeLimit(.minutes(1)))
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
    func regenerateSeededFixtureArtifacts() async throws {
        try FileManager.default.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)

        // Current on-disk state (Base/Helper/Worker/Derived, no `Added.swift`) is both the plain
        // "reindex the seeded codebase" result most journeys need, and what `CompareGitRevisionTests`
        // commits as `HEAD` before adding `Added.swift`.
        let headArtifact = try await CodebaseAnalyzer().enrichedArtifact(at: sampleSwiftPackageDirectory)
        try write(headArtifact, to: "seeded.json")
        try write(headArtifact, to: "comparison-HEAD.json")

        // The working-tree side after the uncommitted `Added.swift` edit.
        let addedFile = sampleSwiftPackageDirectory
            .appendingPathComponent("Sources/SampleSwiftPackage/Added.swift")
        try "public class Added {}\n".write(to: addedFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: addedFile) }
        let currentArtifact = try await CodebaseAnalyzer().enrichedArtifact(at: sampleSwiftPackageDirectory)
        try write(currentArtifact, to: "seeded-with-added.json")
    }

    /// Sorted and indented so a re-record shows only what actually changed — the encoder's key order
    /// is otherwise arbitrary and rewrites the whole file. Only these committed fixtures are written
    /// this way; the app's own persistence is untouched, and decoding ignores both.
    private func write(_ artifact: CodeArtifact, to filename: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(artifact).write(to: artifactsDirectory.appendingPathComponent(filename))
    }
}
