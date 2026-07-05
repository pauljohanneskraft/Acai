import Foundation
import MCP
import Testing
@testable import UMLMCP

/// Covers the tool registry's advertised surface: exactly the ten read-only tools with well-formed,
/// self-describing schemas, and clean dispatch errors.
@Suite("Tool Registry")
struct ToolRegistryTests {

    @Test func advertisesExactlyTheTenReadOnlyTools() {
        let descriptors = ToolRegistry.standard.descriptors
        let names = descriptors.map(\.name).sorted()
        #expect(names == [
            "uml_analyze", "uml_callgraph", "uml_check", "uml_cycles", "uml_deadcode",
            "uml_doctor", "uml_impact", "uml_inspect", "uml_metrics", "uml_smells"
        ])
        // Every tool is read-only, and its description is the autonomous-trigger surface — never empty.
        for descriptor in descriptors {
            #expect(descriptor.annotations.readOnlyHint == true)
            #expect(!(descriptor.description ?? "").isEmpty)
        }
    }

    @Test func everySchemaIsAnObjectRequiringPath() throws {
        for tool in ToolRegistry.standard.tools {
            let schema = try #require(tool.inputSchema.objectValue)
            #expect(schema["type"]?.stringValue == "object")
            let properties = try #require(schema["properties"]?.objectValue)
            #expect(properties["path"] != nil)
            let required = try #require(schema["required"]?.arrayValue).compactMap(\.stringValue)
            #expect(required.contains("path"))
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
