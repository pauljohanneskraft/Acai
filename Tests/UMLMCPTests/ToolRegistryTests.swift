import Foundation
import MCP
import Testing
@testable import UMLMCP

/// Covers the tool registry's advertised surface: the read-only tool set with well-formed,
/// self-describing schemas, and clean dispatch errors.
@Suite("Tool Registry")
struct ToolRegistryTests {

    /// The 14 cross-platform tools; `uml_image` is added on macOS (it links the SwiftUI renderer).
    private var expectedNames: [String] {
        var names = [
            "uml_analyze", "uml_callcycles", "uml_callgraph", "uml_check", "uml_cycles",
            "uml_deadcode", "uml_diagram", "uml_diff", "uml_doctor", "uml_enums",
            "uml_impact", "uml_inspect", "uml_metrics", "uml_smells"
        ]
        #if os(macOS)
        names.append("uml_image")
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
            // Most tools take a single `path`; `uml_diff` compares two (`pathOld`/`pathNew`).
            let pathKeys = tool.name == "uml_diff" ? ["pathOld", "pathNew"] : ["path"]
            for key in pathKeys {
                #expect(properties[key] != nil)
                #expect(required.contains(key))
            }
        }
    }

    @Test func unknownToolIsMethodNotFound() async {
        await #expect(throws: MCPError.self) {
            _ = try await ToolRegistry.standard.call(name: "uml_nope", arguments: nil)
        }
    }

    @Test func missingRequiredArgumentIsInvalidParams() async throws {
        // `uml_impact` requires `type`; omitting it must be rejected before any analysis runs.
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            await #expect(throws: MCPError.self) {
                _ = try await ToolRegistry.standard.call(
                    name: "uml_impact", arguments: ["path": .string(dir.path)])
            }
        }
    }

    @Test func callReturnsBothTextAndStructuredContent() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let result = try await ToolRegistry.standard.call(
                name: "uml_analyze", arguments: ["path": .string(dir.path)])
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
