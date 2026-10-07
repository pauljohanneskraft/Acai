import Foundation
import Testing
import AcaiCore
@testable import AcaiMCP

private final class CountingFixtureParser: CodeParser, @unchecked Sendable {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "fixture") }
    var fileExtensions: [String] { ["fx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    private let lock = NSLock()
    private var count = 0

    var parsedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func parse(source: String, fileName: String) -> CodeArtifact {
        lock.lock()
        count += 1
        lock.unlock()
        let name = (fileName as NSString).lastPathComponent.replacingOccurrences(of: ".fx", with: "")
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

/// Covers the parse-once-per-task contract: a cache hit reuses the snapshot, an edit or `refresh`
/// invalidates it, a missing path is rejected, and a fresh cache instance starts warm from the
/// shared `AnalysisStore` instead of re-parsing. Every cache here is built with its own temp-directory
/// store — never `AnalysisStore.standard` — so tests never touch the real `~/.acai/analysis`.
@Suite("Analysis Snapshot Cache")
struct AnalysisSnapshotCacheTests {

    @Test func reusesSnapshotWhenTreeUnchanged() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache(store: MCPTestSupport.freshStore())
            _ = try await cache.artifact(path: dir.path)
            _ = try await cache.artifact(path: dir.path)
            #expect(await cache.analysisCount == 1)
        }
    }

    @Test func refreshForcesReanalysis() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache(store: MCPTestSupport.freshStore())
            _ = try await cache.artifact(path: dir.path)
            _ = try await cache.artifact(path: dir.path, refresh: true)
            #expect(await cache.analysisCount == 2)
        }
    }

    /// `refresh` has to reach past the per-file cache too, or a "forced re-parse" would quietly
    /// replay the fragments that cache already holds and there would be no way to get a cold one.
    @Test func refreshReparsesFilesRatherThanReplayingCachedFragments() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            for (name, content) in [("A.fx", "one"), ("B.fx", "two")] {
                let file = dir.appendingPathComponent(name)
                try content.write(to: file, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: file.path)
            }
            let parser = CountingFixtureParser()
            let cache = AnalysisSnapshotCache(
                service: AnalysisService(parsers: [parser]), store: MCPTestSupport.freshStore())

            _ = try await cache.artifact(path: dir.path)
            #expect(parser.parsedCount == 2)

            _ = try await cache.artifact(path: dir.path, refresh: true)
            #expect(parser.parsedCount == 4, "a forced re-parse must read both files again, not reuse fragments")
        }
    }

    @Test func editInvalidatesSnapshot() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache(store: MCPTestSupport.freshStore())
            let first = try await cache.artifact(path: dir.path)
            #expect(first.flattened().count == 2)

            // Add a third type; the fingerprint changes, so the next call re-parses.
            try "class Extra {}".write(
                to: dir.appendingPathComponent("Extra.swift"), atomically: true, encoding: .utf8)
            let second = try await cache.artifact(path: dir.path)
            #expect(await cache.analysisCount == 2)
            #expect(second.flattened().count == 3)
        }
    }

    @Test func renameInvalidatesSnapshotDespiteSameMtimeAndCount() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            let file = try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache(store: MCPTestSupport.freshStore())
            _ = try await cache.artifact(path: dir.path)

            // Rename the file, restoring its original mtime so `latestModification` and `fileCount`
            // are both unchanged — only the path digest can catch the move.
            let mtime = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
            let renamed = dir.appendingPathComponent("Renamed.swift")
            try FileManager.default.moveItem(at: file, to: renamed)
            try FileManager.default.setAttributes([.modificationDate: mtime as Any], ofItemAtPath: renamed.path)

            _ = try await cache.artifact(path: dir.path)
            #expect(await cache.analysisCount == 2)
        }
    }

    @Test func missingPathThrows() async {
        let cache = AnalysisSnapshotCache(store: MCPTestSupport.freshStore())
        await #expect(throws: (any Error).self) {
            _ = try await cache.artifact(path: "/no/such/path-\(UUID().uuidString)")
        }
    }

    /// A `.json` baseline whose `schemaVersion` is newer than this build understands names both the
    /// found and expected versions, rather than being misread or failing some unrelated way downstream.
    @Test func jsonBaselineFromANewerSchemaVersionNamesBothVersions() async throws {
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift))
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(artifact)) as? [String: Any]
        )
        json["schemaVersion"] = 999
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("future-schema-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = AnalysisSnapshotCache(store: MCPTestSupport.freshStore())
        var thrown: Error?
        do {
            _ = try await cache.artifact(path: url.path)
        } catch {
            thrown = error
        }
        let message = String(describing: try #require(thrown))
        #expect(message.contains("999"))
        #expect(message.contains("\(CodeArtifact.currentSchemaVersion)"))
    }

    @Test func fingerprintChangesOnRenameWithPreservedMtime() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiMCP-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try MCPTestSupport.writeSampleSwiftSource(in: dir)
        let before = SourceTreeFingerprint(directory: dir).compute()

        let mtime = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
        let renamed = dir.appendingPathComponent("Renamed.swift")
        try FileManager.default.moveItem(at: file, to: renamed)
        try FileManager.default.setAttributes([.modificationDate: mtime as Any], ofItemAtPath: renamed.path)

        let after = SourceTreeFingerprint(directory: dir).compute()
        #expect(after != before)
    }

    @Test func fingerprintChangesWithContentAndCount() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiMCP-sig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try MCPTestSupport.writeSampleSwiftSource(in: dir)
        let before = SourceTreeFingerprint(directory: dir).compute()
        #expect(SourceTreeFingerprint(directory: dir).compute() == before)

        try "class Extra {}".write(
            to: dir.appendingPathComponent("Extra.swift"), atomically: true, encoding: .utf8)
        #expect(SourceTreeFingerprint(directory: dir).compute() != before)
    }

    // MARK: - Shared store

    @Test func startsWarmFromAnAlreadyStoredAnalysis() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let store = MCPTestSupport.freshStore()
            let resolvedPath = dir.resolvingSymlinksInPath().path
            let artifact = try await AnalysisService.standard.analyzeProject(at: dir, allowedLanguages: [])
            let fingerprint = SourceTreeFingerprint(directory: dir).compute()
            try store.write(artifact, sourcePath: resolvedPath, fingerprint: fingerprint)

            let cache = AnalysisSnapshotCache(store: store)
            _ = try await cache.artifact(path: dir.path)
            #expect(await cache.analysisCount == 0)
        }
    }

    @Test func writesBackWhatItAnalyzesForTheNextSessionToReuse() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let store = MCPTestSupport.freshStore()

            let first = AnalysisSnapshotCache(store: store)
            _ = try await first.artifact(path: dir.path)

            let second = AnalysisSnapshotCache(store: store)
            _ = try await second.artifact(path: dir.path)
            #expect(await second.analysisCount == 0)
        }
    }

    @Test func aStaleStoredAnalysisIsReanalyzedNotReturnedAsCurrent() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let store = MCPTestSupport.freshStore()
            let resolvedPath = dir.resolvingSymlinksInPath().path
            let artifact = try await AnalysisService.standard.analyzeProject(at: dir, allowedLanguages: [])
            // A fingerprint that can never match the real tree.
            let staleFingerprint = CodeStateFingerprint.fileSystem(
                latestModification: .distantPast, fileCount: 999, contentDigest: 0)
            try store.write(artifact, sourcePath: resolvedPath, fingerprint: staleFingerprint)

            let cache = AnalysisSnapshotCache(store: store)
            _ = try await cache.artifact(path: dir.path)
            #expect(await cache.analysisCount == 1)
        }
    }
}
