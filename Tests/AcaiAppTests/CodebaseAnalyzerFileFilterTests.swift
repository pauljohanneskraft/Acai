import Foundation
import Testing
@testable import AcaiApp

/// The actual "applied at indexing time in `CodebaseAnalyzer`" integration the backlog names for
/// B62: a blocked file is excluded before real Swift parsing runs, exercised end-to-end through
/// `CodebaseAnalyzer.enrichedArtifact(at:fileFilter:)` — the same call the live reindex path makes.
@Suite("CodebaseAnalyzer file filter")
struct CodebaseAnalyzerFileFilterTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiAppFileFilterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A blocked file's type never appears in the indexed artifact")
    func blockedFileIsExcludedFromIndexing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "class Keep {}\n".write(to: dir.appendingPathComponent("Keep.swift"), atomically: true, encoding: .utf8)
        let generated = dir.appendingPathComponent("Generated", isDirectory: true)
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try "class Skip {}\n".write(
            to: generated.appendingPathComponent("Skip.swift"), atomically: true, encoding: .utf8
        )

        let filter = FileFilter(rules: [.init(pattern: "Generated/*", syntax: .glob, action: .block)])
        let artifact = try CodebaseAnalyzer().enrichedArtifact(at: dir, fileFilter: filter)

        #expect(artifact.types.contains { $0.name == "Keep" })
        #expect(!artifact.types.contains { $0.name == "Skip" })
    }

    @Test("A nil file filter indexes every file, unchanged from before this existed")
    func nilFilterIndexesEverything() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "class Foo {}\n".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)

        let artifact = try CodebaseAnalyzer().enrichedArtifact(at: dir, fileFilter: nil)
        #expect(artifact.types.contains { $0.name == "Foo" })
    }
}
