import Foundation
import MCP
import Testing
import UMLLibrary
@testable import UMLMCP

/// Covers the tools that brought the MCP to parity with the CLI: diff, call-cycles, enums, diagram,
/// and (macOS) image.
@Suite("Parity Tools")
struct ParityToolsTests {

    @Test func diffReportsAddedTypes() async throws {
        try await MCPTestSupport.withTempDirectory { old in
            try await MCPTestSupport.withTempDirectory { new in
                try MCPTestSupport.writeSampleSwiftSource(in: old)
                try MCPTestSupport.writeSampleSwiftSource(in: new)
                try "class Added {}".write(
                    to: new.appendingPathComponent("Added.swift"), atomically: true, encoding: .utf8)
                let result = try await ToolRegistry.standard.call(
                    name: "uml_diff",
                    arguments: ["pathOld": .string(old.path), "pathNew": .string(new.path)])
                let object = try #require(result.structuredContent?.objectValue)
                let addedIDs = (object["addedTypes"]?.arrayValue ?? [])
                    .compactMap { $0.objectValue?["id"]?.stringValue ?? $0.stringValue }
                #expect(addedIDs.contains { $0.contains("Added") })
            }
        }
    }

    @Test func diffAcceptsAJSONBaseline() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            // Persist an artifact baseline, then diff the live tree against that .json file.
            let artifact = try AnalysisService.standard.analyzeProject(at: dir, allowedLanguages: [])
            let encoder = JSONEncoder()
            let baseline = dir.appendingPathComponent("baseline.json")
            try encoder.encode(artifact).write(to: baseline)
            let result = try await ToolRegistry.standard.call(
                name: "uml_diff",
                arguments: ["pathOld": .string(baseline.path), "pathNew": .string(dir.path)])
            #expect(result.structuredContent?.objectValue != nil)
        }
    }

    @Test func callCyclesReturnsAnArray() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call("uml_callcycles", on: .standard, path: dir)
            #expect(value.arrayValue != nil)  // no method cycles in the fixture, but a well-formed list
        }
    }

    @Test func enumsListsCasesWithLocation() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try "enum Direction { case north, south }".write(
                to: dir.appendingPathComponent("Direction.swift"), atomically: true, encoding: .utf8)
            let value = try await MCPTestSupport.call("uml_enums", on: .standard, path: dir)
            let entries = try #require(value.arrayValue)
            let direction = try #require(entries.first { $0.objectValue?["type"]?.stringValue == "Direction" })
            let cases = try #require(direction.objectValue?["cases"]?.arrayValue)
            #expect(cases.count == 2)
        }
    }

    @Test func diagramRendersMermaidAndDot() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let mermaid = try await MCPTestSupport.callResult(
                "uml_diagram", on: .standard, path: dir, ["kind": .string("class"), "format": .string("mermaid")])
            #expect(MCPTestSupport.firstText(mermaid).contains("classDiagram"))
            let dot = try await MCPTestSupport.callResult(
                "uml_diagram", on: .standard, path: dir, ["kind": .string("class"), "format": .string("dot")])
            #expect(MCPTestSupport.firstText(dot).contains("digraph"))
        }
    }

    #if os(macOS)
    @Test func imageRendersNonEmptyPNG() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let result = try await MCPTestSupport.callResult(
                "uml_image", on: .standard, path: dir, ["kind": .string("class")])
            let content = try #require(result.content.first)
            guard case let .image(data, mimeType, _, _) = content else {
                Issue.record("expected image content")
                return
            }
            #expect(mimeType == "image/png")
            #expect(Data(base64Encoded: data)?.isEmpty == false)
        }
    }
    #endif
}
