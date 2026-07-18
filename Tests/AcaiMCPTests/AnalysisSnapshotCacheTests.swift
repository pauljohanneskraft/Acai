import Foundation
import Testing
@testable import AcaiMCP

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

    @Test func renameInvalidatesSnapshotDespiteSameMtimeAndCount() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            let file = try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let cache = AnalysisSnapshotCache()
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

    @Test func signatureChangesOnRenameWithPreservedMtime() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiMCP-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try MCPTestSupport.writeSampleSwiftSource(in: dir)
        let before = SourceTreeSignature(root: dir)

        let mtime = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
        let renamed = dir.appendingPathComponent("Renamed.swift")
        try FileManager.default.moveItem(at: file, to: renamed)
        try FileManager.default.setAttributes([.modificationDate: mtime as Any], ofItemAtPath: renamed.path)

        let after = SourceTreeSignature(root: dir)
        #expect(after != before)                                 // the move shifts the signature
        #expect(after.contentDigest != before.contentDigest)     // ...specifically via the path digest
        #expect(after.fileCount == before.fileCount)             // ...even though the file count is unchanged
    }

    @Test func missingPathThrows() async {
        let cache = AnalysisSnapshotCache()
        await #expect(throws: (any Error).self) {
            _ = try await cache.artifact(path: "/no/such/path-\(UUID().uuidString)")
        }
    }

    @Test func signatureChangesWithContentAndCount() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiMCP-sig-\(UUID().uuidString)", isDirectory: true)
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
