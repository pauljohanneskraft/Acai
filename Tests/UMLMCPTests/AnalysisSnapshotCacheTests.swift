import Foundation
import Testing
@testable import UMLMCP

/// Covers the parse-once-per-task contract: a cache hit reuses the snapshot, an edit or `refresh`
/// invalidates it, and a missing path is rejected.
@Suite("Analysis Snapshot Cache")
struct AnalysisSnapshotCacheTests {

    @Test func reusesSnapshotWhenTreeUnchanged() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache()
            _ = try await cache.artifact(path: dir.path)
            _ = try await cache.artifact(path: dir.path)
            // Second call is a cache hit — only one real analysis ran.
            #expect(await cache.analysisCount == 1)
        }
    }

    @Test func refreshForcesReanalysis() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache()
            _ = try await cache.artifact(path: dir.path)
            _ = try await cache.artifact(path: dir.path, refresh: true)
            #expect(await cache.analysisCount == 2)
        }
    }

    @Test func editInvalidatesSnapshot() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache()
            let first = try await cache.artifact(path: dir.path)
            #expect(first.flattened().count == 2)

            // Add a third type; the tree signature changes, so the next call re-parses.
            try "class Extra {}".write(
                to: dir.appendingPathComponent("Extra.swift"), atomically: true, encoding: .utf8)
            let second = try await cache.artifact(path: dir.path)
            #expect(await cache.analysisCount == 2)
            #expect(second.flattened().count == 3)
        }
    }

    @Test func missingPathThrows() async {
        let cache = AnalysisSnapshotCache()
        await #expect(throws: (any Error).self) {
            _ = try await cache.artifact(path: "/no/such/path-\(UUID().uuidString)")
        }
    }

    @Test func signatureChangesWithContentAndCount() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMLMCP-sig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try MCPTestSupport.writeSampleSwiftSource(in: dir)
        let before = SourceTreeSignature(root: dir)
        #expect(SourceTreeSignature(root: dir) == before)  // stable when nothing changes

        try "class Extra {}".write(
            to: dir.appendingPathComponent("Extra.swift"), atomically: true, encoding: .utf8)
        #expect(SourceTreeSignature(root: dir) != before)  // a new file shifts the signature
    }
}
