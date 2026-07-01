import Foundation
import Testing
@testable import UMLMCP

@Suite("Snapshot Cache")
struct SnapshotCacheTests {

    @Test func cachesArtifactByPathAndMtime() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMLMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("Sample.swift")
        try "class Foo {}".write(to: file, atomically: true, encoding: .utf8)

        let cache = SnapshotCache()
        let first = try await cache.artifact(at: dir.path)
        let second = try await cache.artifact(at: dir.path)
        #expect(first.types.count == second.types.count)
    }

    @Test func throwsForNonexistentPath() async {
        let cache = SnapshotCache()
        do {
            _ = try await cache.artifact(at: "/nonexistent-\(UUID().uuidString)")
            Issue.record("Expected an error for nonexistent path")
        } catch {
            #expect(String(describing: error).contains("does not exist"))
        }
    }
}

@Suite("Tool Dispatcher")
struct ToolDispatcherTests {

    @Test func unknownToolReturnsError() async {
        let dispatcher = ToolDispatcher(cache: SnapshotCache())
        let result = await dispatcher.dispatch(name: "uml_nonexistent", arguments: nil)
        #expect(result.isError == true)
    }

    @Test func analyzeMissingPathReturnsError() async {
        let dispatcher = ToolDispatcher(cache: SnapshotCache())
        let result = await dispatcher.dispatch(name: "uml_analyze", arguments: [:])
        #expect(result.isError == true)
    }

    @Test func analyzeReturnsValidSummary() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMLMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("Sample.swift")
        try """
        class Service {
            let repo: Repository = Repository()
            func run() { repo.save() }
        }
        class Repository {
            func save() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let dispatcher = ToolDispatcher(cache: SnapshotCache())
        let result = await dispatcher.dispatch(
            name: "uml_analyze", arguments: ["path": .string(dir.path)])
        #expect(result.isError != true)
        let text = result.content.first.flatMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }
        #expect(text?.contains("totalTypes") == true)
    }

    @Test func metricsReturnsJSON() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMLMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "class A { func x() {} }".write(
            to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)

        let dispatcher = ToolDispatcher(cache: SnapshotCache())
        let result = await dispatcher.dispatch(
            name: "uml_metrics", arguments: ["path": .string(dir.path)])
        #expect(result.isError != true)
        let text = result.content.first.flatMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }
        #expect(text?.contains("counts") == true)
    }

    @Test func cyclesReturnsJSON() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMLMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "class B {}".write(
            to: dir.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)

        let dispatcher = ToolDispatcher(cache: SnapshotCache())
        let result = await dispatcher.dispatch(
            name: "uml_cycles", arguments: ["path": .string(dir.path)])
        #expect(result.isError != true)
    }
}
