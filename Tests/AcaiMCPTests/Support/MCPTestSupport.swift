import Foundation
import MCP
import Testing
@testable import AcaiMCP

/// Shared helpers for driving the MCP tools in-process. Fixtures live under a unique temp directory
/// that the caller removes; tests never touch the user's config.
enum MCPTestSupport {

    /// Runs `body` with a fresh temp directory that is removed afterwards.
    static func withTempDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    /// Writes a two-type Swift source (Service depends on Repository) into `directory` — enough to
    /// exercise metrics, impact, call graph, and inspection.
    @discardableResult
    static func writeSampleSwiftSource(in directory: URL) throws -> URL {
        let source = """
        class Service {
            let repository: Repository = Repository()
            func run(times: Int, label: String, flag: Bool, extra: Double, more: [Int], last: String) {
                repository.save()
            }
        }

        class Repository {
            func save() {}
        }
        """
        let fileURL = directory.appendingPathComponent("Sample.swift")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// The arguments object for a tool call over `directory`, merged with any extras.
    static func arguments(path: URL, _ extra: [String: Value] = [:]) -> [String: Value] {
        var values: [String: Value] = ["path": .string(path.path)]
        for (key, value) in extra {
            values[key] = value
        }
        return values
    }

    /// Calls a tool by name through the registry and returns its structured JSON payload.
    static func call(
        _ name: String, on registry: ToolRegistry, path: URL, _ extra: [String: Value] = [:]
    ) async throws -> Value {
        let result = try await registry.call(name: name, arguments: arguments(path: path, extra))
        return try #require(result.structuredContent)
    }

    /// Calls a tool and returns the whole result — for content-returning tools (`acai_diagram`,
    /// `acai_image`) that emit text/image content rather than structured JSON.
    static func callResult(
        _ name: String, on registry: ToolRegistry, path: URL, _ extra: [String: Value] = [:]
    ) async throws -> CallTool.Result {
        try await registry.call(name: name, arguments: arguments(path: path, extra))
    }

    /// The text of a tool result's first content item, or a recorded failure.
    static func firstText(_ result: CallTool.Result) -> String {
        if case let .text(text, _, _) = result.content.first {
            return text
        }
        Issue.record("expected text content")
        return ""
    }
}
