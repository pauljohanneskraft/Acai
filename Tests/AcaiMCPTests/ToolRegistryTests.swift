import Foundation
import MCP
import Testing
@testable import AcaiMCP

/// Covers the tool registry's advertised surface: the read-only tool set with well-formed,
/// self-describing schemas, and clean dispatch errors.
@Suite("Tool Registry")
struct ToolRegistryTests {

    /// The 8 cross-platform tools; `acai_image` is added on macOS (it links the SwiftUI renderer).
    private var expectedNames: [String] {
        var names = [
            "acai_analyze", "acai_callgraph", "acai_diagram", "acai_diff",
            "acai_impact", "acai_inspect", "acai_metrics", "acai_quality"
        ]
        #if os(macOS)
        names.append("acai_image")
        #endif
        return names.sorted()
    }

    @Test func advertisesTheReadOnlyToolSet() {
        let descriptors = ToolRegistry.standard.descriptors
        #expect(descriptors.map(\.name).sorted() == expectedNames)
        // Every tool is read-only, and its description is the autonomous-trigger surface — never empty.
        for descriptor in descriptors {
            #expect(descriptor.annotations.readOnlyHint == true)
            #expect(!(descriptor.description ?? "").isEmpty)
        }
    }

    @Test func everySchemaIsAnObjectWithRequiredPathInputs() throws {
        for tool in ToolRegistry.standard.tools {
            let schema = try #require(tool.inputSchema.objectValue)
            #expect(schema["type"]?.stringValue == "object")
            let properties = try #require(schema["properties"]?.objectValue)
            let required = try #require(schema["required"]?.arrayValue).compactMap(\.stringValue)
            // Most tools take a single `path`; `acai_diff` compares two (`pathOld`/`pathNew`).
            let pathKeys = tool.name == "acai_diff" ? ["pathOld", "pathNew"] : ["path"]
            for key in pathKeys {
                #expect(properties[key] != nil)
                #expect(required.contains(key))
            }
        }
    }

    @Test func unknownToolIsMethodNotFound() async {
        await #expect(throws: MCPError.self) {
            _ = try await ToolRegistry.standard.call(name: "acai_nope", arguments: nil)
        }
    }

    @Test func missingRequiredArgumentIsInvalidParams() async throws {
        // `acai_impact` requires `type`; omitting it must be rejected before any analysis runs.
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            await #expect(throws: MCPError.self) {
                _ = try await ToolRegistry.standard.call(
                    name: "acai_impact", arguments: ["path": .string(dir.path)])
            }
        }
    }

    /// MCP requires `structuredContent` to be a JSON object. The tools whose report is a top-level
    /// list (`acai_inspect`'s rows, `acai_callgraph --mode cycles`' clusters) must wrap it in an object
    /// envelope — a bare array is rejected by the client's schema validation. Guards the regression
    /// that made half the tools unusable from an MCP client.
    @Test func listReportingToolsWrapStructuredContentInAnObject() async throws {
        let listCalls: [(String, [String: Value])] = [
            ("acai_inspect", [:]),
            ("acai_callgraph", ["mode": .string("cycles")])
        ]
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            for (name, extraArgs) in listCalls {
                var arguments: [String: Value] = ["path": .string(dir.path)]
                arguments.merge(extraArgs) { _, new in new }
                let result = try await ToolRegistry.standard.call(name: name, arguments: arguments)
                let structured = try #require(
                    result.structuredContent, "\(name) must attach structuredContent")
                #expect(
                    structured.objectValue != nil,
                    "\(name) structuredContent must be a JSON object, not \(structured)")
                #expect(structured.objectValue?["items"]?.arrayValue != nil, "\(name) missing items list")
            }
        }
    }

    @Test func callReturnsBothTextAndStructuredContent() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let result = try await ToolRegistry.standard.call(
                name: "acai_analyze", arguments: ["path": .string(dir.path)])
            #expect(result.structuredContent != nil)
            let text = try #require(result.content.first)
            if case let .text(text, _, _) = text {
                #expect(text.contains("typeCount"))
            } else {
                Issue.record("expected text content")
            }
        }
    }
}
