import Foundation
import MCP
import Testing
@testable import AcaiMCP

/// Every dispatchable tool's four argument-failure modes: a path that does not exist, an argument of
/// the wrong JSON type, an unknown language, and each required argument omitted in turn.
///
/// Driven off each tool's own `inputSchema` rather than a hand-kept table, so a tool added later is
/// swept without touching this file — and a tool that introduces a required argument this suite has
/// no fixture value for fails here rather than going uncovered.
@Suite("Tool Error Paths")
struct ToolErrorPathTests {

    /// A value satisfying `key` for any tool that requires it.
    private func fixtureValue(for key: String, in directory: URL) -> Value? {
        switch key {
        case "path", "pathOld", "pathNew":
            .string(directory.path)
        case "output":
            .string(directory.appendingPathComponent("atlas.pdf").path)
        case "type":
            .string("Repository")
        default:
            nil
        }
    }

    private func isPathKey(_ key: String) -> Bool {
        key == "path" || key == "pathOld" || key == "pathNew"
    }

    private func requiredKeys(of tool: any AnalysisTool) throws -> [String] {
        let schema = try #require(tool.inputSchema.objectValue, "\(tool.name) schema")
        return try #require(schema["required"]?.arrayValue, "\(tool.name) required")
            .compactMap(\.stringValue)
    }

    /// The smallest argument set that gets `tool` past its required-argument checks.
    private func validArguments(for tool: any AnalysisTool, in directory: URL) throws -> [String: Value] {
        var values: [String: Value] = [:]
        for key in try requiredKeys(of: tool) {
            guard let value = fixtureValue(for: key, in: directory) else {
                Issue.record("\(tool.name) requires '\(key)', which this suite has no fixture value for")
                continue
            }
            values[key] = value
        }
        return values
    }

    /// The `invalidParams` detail the call failed with, or `nil` after recording the mismatch.
    private func rejection(
        of toolName: String, with values: [String: Value], on registry: ToolRegistry
    ) async -> String? {
        let error = await #expect(throws: MCPError.self) {
            _ = try await registry.call(name: toolName, arguments: values)
        }
        guard case .invalidParams(let detail) = error else {
            Issue.record("\(toolName): expected invalidParams, got \(String(describing: error))")
            return nil
        }
        guard let detail, !detail.isEmpty else {
            Issue.record("\(toolName): invalidParams carried no message")
            return nil
        }
        return detail
    }

    private func sweep(
        _ body: (any AnalysisTool, ToolRegistry, URL) async throws -> Void
    ) async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            // Guards the sweeps themselves: an empty registry would pass every one vacuously.
            #expect(registry.tools.count >= 9)
            for tool in registry.tools {
                try await body(tool, registry, directory)
            }
        }
    }

    @Test("A path that does not exist is reported with the path, not swallowed or crashed on")
    func nonexistentPathIsReported() async throws {
        try await sweep { tool, registry, directory in
            let missing = directory.appendingPathComponent("no-such-tree-\(UUID().uuidString)")
            var values = try validArguments(for: tool, in: directory)
            for key in values.keys where isPathKey(key) {
                values[key] = .string(missing.path)
            }
            let detail = try #require(
                await rejection(of: tool.name, with: values, on: registry), "\(tool.name)")
            #expect(detail.contains(missing.lastPathComponent), "\(tool.name): \(detail)")
        }
    }

    @Test("A path of the wrong JSON type is reported as a type error, not as a missing argument")
    func mistypedPathIsReportedAsSuch() async throws {
        try await sweep { tool, registry, directory in
            var values = try validArguments(for: tool, in: directory)
            let pathKeys = values.keys.filter(isPathKey)
            for key in pathKeys {
                values[key] = .int(1)
            }
            let detail = try #require(
                await rejection(of: tool.name, with: values, on: registry), "\(tool.name)")
            #expect(detail.contains("must be a string"), "\(tool.name): \(detail)")
            #expect(pathKeys.contains { detail.contains("'\($0)'") }, "\(tool.name): \(detail)")
        }
    }

    @Test("A boolean argument given a string is rejected rather than silently ignored")
    func mistypedBooleanIsRejected() async throws {
        try await sweep { tool, registry, directory in
            // Every tool advertises `refresh`; a tool that stopped reading it would pass vacuously.
            let properties = tool.inputSchema.objectValue?["properties"]?.objectValue
            #expect(properties?["refresh"]?.objectValue?["type"]?.stringValue == "boolean", "\(tool.name)")
            var values = try validArguments(for: tool, in: directory)
            values["refresh"] = .string("true")
            let detail = try #require(
                await rejection(of: tool.name, with: values, on: registry), "\(tool.name)")
            #expect(detail.contains("'refresh'"), "\(tool.name): \(detail)")
            #expect(detail.contains("must be a boolean"), "\(tool.name): \(detail)")
        }
    }

    @Test("An unknown language names the languages the build actually supports")
    func unknownLanguageIsReported() async throws {
        try await sweep { tool, registry, directory in
            var values = try validArguments(for: tool, in: directory)
            values["languages"] = .array([.string("cobol")])
            let detail = try #require(
                await rejection(of: tool.name, with: values, on: registry), "\(tool.name)")
            #expect(detail.contains("'cobol'"), "\(tool.name): \(detail)")
            #expect(
                detail.contains(SourceLanguageResolver().names.joined(separator: ", ")),
                "\(tool.name): \(detail)")
        }
    }

    @Test("Each required argument, omitted, is reported by name")
    func eachOmittedRequiredArgumentIsNamed() async throws {
        try await sweep { tool, registry, directory in
            let keys = try requiredKeys(of: tool)
            #expect(!keys.isEmpty, "\(tool.name) declares no required arguments")
            for omitted in keys {
                var values = try validArguments(for: tool, in: directory)
                values[omitted] = nil
                let detail = try #require(
                    await rejection(of: tool.name, with: values, on: registry),
                    "\(tool.name) without '\(omitted)'")
                #expect(detail.contains("'\(omitted)'"), "\(tool.name) without '\(omitted)': \(detail)")
            }
        }
    }

    @Test("An empty required argument is reported as empty rather than as absent")
    func emptyRequiredArgumentIsReportedAsEmpty() async throws {
        let registry = MCPTestSupport.testRegistry
        let detail = try #require(
            await rejection(of: "acai_analyze", with: ["path": .string("")], on: registry))
        #expect(detail.contains("'path'"))
        #expect(detail.contains("must not be empty"))
    }

    @Test("A mistyped selector facet is rejected instead of widening the selection to everything")
    func mistypedSelectorFacetIsRejected() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let registry = MCPTestSupport.testRegistry
            for facet in ["module", "type", "stereotype", "annotation"] {
                let detail = try #require(
                    await rejection(
                        of: "acai_inspect",
                        with: ["path": .string(directory.path), facet: .int(3)],
                        on: registry),
                    "\(facet)")
                #expect(detail.contains("'\(facet)'"), "\(facet): \(detail)")
                #expect(detail.contains("must be a string"), "\(facet): \(detail)")
            }
        }
    }
}
