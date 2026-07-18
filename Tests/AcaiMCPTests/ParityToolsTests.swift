import Foundation
import MCP
import Testing
import AcaiLibrary
@testable import AcaiMCP

/// Covers the tools that brought the MCP to parity with the CLI: diff, callgraph cycles mode, inspect
/// enums mode, diagram, and (macOS) image.
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
                    name: "acai_diff",
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
                name: "acai_diff",
                arguments: ["pathOld": .string(baseline.path), "pathNew": .string(dir.path)])
            #expect(result.structuredContent?.objectValue != nil)
        }
    }

    @Test func callGraphCyclesModeReturnsAnArray() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call(
                "acai_callgraph", on: .standard, path: dir, ["mode": .string("cycles")])
            // no method cycles in the fixture, but a well-formed list inside the `items` envelope
            #expect(value.objectValue?["items"]?.arrayValue != nil)
        }
    }

    @Test func inspectEnumsModeListsCasesWithLocation() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try "enum Direction { case north, south }".write(
                to: dir.appendingPathComponent("Direction.swift"), atomically: true, encoding: .utf8)
            let value = try await MCPTestSupport.call(
                "acai_inspect", on: .standard, path: dir, ["enums": .bool(true)])
            let entries = try #require(value.objectValue?["items"]?.arrayValue)
            let direction = try #require(entries.first { $0.objectValue?["type"]?.stringValue == "Direction" })
            let cases = try #require(direction.objectValue?["cases"]?.arrayValue)
            #expect(cases.count == 2)
        }
    }

    @Test func diagramRendersMermaidAndDot() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let mermaid = try await MCPTestSupport.callResult(
                "acai_diagram", on: .standard, path: dir, ["kind": .string("class"), "format": .string("mermaid")])
            #expect(MCPTestSupport.firstText(mermaid).contains("classDiagram"))
            let dot = try await MCPTestSupport.callResult(
                "acai_diagram", on: .standard, path: dir, ["kind": .string("class"), "format": .string("dot")])
            #expect(MCPTestSupport.firstText(dot).contains("digraph"))
        }
    }

    #if os(macOS)
    @Test func imageRendersNonEmptyPNG() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let result = try await MCPTestSupport.callResult(
                "acai_image", on: .standard, path: dir, ["kind": .string("class")])
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
