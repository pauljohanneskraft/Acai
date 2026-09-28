import Foundation
import MCP
import Testing
import AcaiLibrary
@testable import AcaiMCP
#if os(macOS)
import AcaiRender
#endif

/// Covers the tools that brought the MCP to parity with the CLI: diff, callgraph cycles mode, inspect
/// enums mode, diagram, and (macOS) image and atlas.
@Suite("Parity Tools")
struct ParityToolsTests {

    @Test func diffReportsAddedTypes() async throws {
        try await MCPTestSupport.withTempDirectory { old in
            try await MCPTestSupport.withTempDirectory { new in
                try MCPTestSupport.writeSampleSwiftSource(in: old)
                try MCPTestSupport.writeSampleSwiftSource(in: new)
                try "class Added {}".write(
                    to: new.appendingPathComponent("Added.swift"), atomically: true, encoding: .utf8)
                let result = try await MCPTestSupport.testRegistry.call(
                    name: "acai_diff",
                    arguments: ["pathOld": .string(old.path), "pathNew": .string(new.path)])
                let object = try #require(result.structuredContent?.objectValue)
                let diff = try #require(object["diff"]?.objectValue)
                let addedIDs = (diff["addedTypes"]?.arrayValue ?? [])
                    .compactMap { $0.objectValue?["id"]?.stringValue ?? $0.stringValue }
                #expect(addedIDs.contains { $0.contains("Added") })
                #expect(object["health"] != nil)
            }
        }
    }

    @Test func diffAcceptsAJSONBaseline() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let artifact = try await AnalysisService.standard.analyzeProject(at: dir, allowedLanguages: [])
            let encoder = JSONEncoder()
            let baseline = dir.appendingPathComponent("baseline.json")
            try encoder.encode(artifact).write(to: baseline)
            let result = try await MCPTestSupport.testRegistry.call(
                name: "acai_diff",
                arguments: ["pathOld": .string(baseline.path), "pathNew": .string(dir.path)])
            #expect(result.structuredContent?.objectValue != nil)
        }
    }

    @Test func callGraphCyclesModeReturnsAnArray() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call(
                "acai_callgraph", on: MCPTestSupport.testRegistry, path: dir, ["mode": .string("cycles")])
            // no method cycles in the fixture, but a well-formed list alongside `health`
            #expect(value.objectValue?["cycles"]?.arrayValue != nil)
            #expect(value.objectValue?["health"] != nil)
        }
    }

    @Test func inspectEnumsModeListsCasesWithLocation() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try "enum Direction { case north, south }".write(
                to: dir.appendingPathComponent("Direction.swift"), atomically: true, encoding: .utf8)
            let value = try await MCPTestSupport.call(
                "acai_inspect", on: MCPTestSupport.testRegistry, path: dir, ["enums": .bool(true)])
            let entries = try #require(value.objectValue?["enums"]?.arrayValue)
            let direction = try #require(entries.first { $0.objectValue?["type"]?.stringValue == "Direction" })
            let cases = try #require(direction.objectValue?["cases"]?.arrayValue)
            #expect(cases.count == 2)
            #expect(value.objectValue?["health"] != nil)
        }
    }

    @Test func diagramRendersMermaidAndDot() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let registry = MCPTestSupport.testRegistry
            let mermaid = try await MCPTestSupport.callResult(
                "acai_diagram", on: registry, path: dir, ["kind": .string("class"), "format": .string("mermaid")])
            #expect(MCPTestSupport.firstText(mermaid).contains("classDiagram"))
            let dot = try await MCPTestSupport.callResult(
                "acai_diagram", on: registry, path: dir, ["kind": .string("class"), "format": .string("dot")])
            #expect(MCPTestSupport.firstText(dot).contains("digraph"))
        }
    }

    @Test func diagramAddsLowTrustNoticeBeforeDiagramText() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeLowTrustSwiftSource(in: dir)
            let result = try await MCPTestSupport.callResult(
                "acai_diagram", on: MCPTestSupport.testRegistry, path: dir,
                ["kind": .string("class"), "format": .string("dot")])
            #expect(result.content.count == 2)
            #expect(MCPTestSupport.firstText(result).contains("Parse health"))
            guard case let .text(diagram, _, _) = result.content.last else {
                Issue.record("expected diagram text as the last content item")
                return
            }
            #expect(diagram.contains("digraph"))
        }
    }

    #if os(macOS)
    @Test func imageRendersNonEmptyPNG() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let result = try await MCPTestSupport.callResult(
                "acai_image", on: MCPTestSupport.testRegistry, path: dir, ["kind": .string("class")])
            let content = try #require(result.content.first)
            guard case let .image(data, mimeType, _, _) = content else {
                Issue.record("expected image content")
                return
            }
            #expect(mimeType == "image/png")
            #expect(Data(base64Encoded: data)?.isEmpty == false)
        }
    }

    @Test func atlasWritesAVersionedPDF() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("atlas.pdf")
            let value = try await MCPTestSupport.call(
                "acai_atlas", on: MCPTestSupport.testRegistry, path: dir, ["output": .string(output.path)])
            let object = try #require(value.objectValue)
            #expect(object["path"]?.stringValue == output.standardizedFileURL.path)
            #expect(object["formatVersion"]?.intValue == AtlasDocument.formatVersion)
            #expect(object["diagramCount"]?.intValue == 3)
            let data = try Data(contentsOf: output)
            #expect(data.starts(with: Data("%PDF".utf8)))
        }
    }

    @Test func atlasRejectsAMissingRulesFile() async throws {
        try await expectAtlasInvalidParams([
            "rules": .string("/nonexistent/quality.yml")
        ])
    }

    @Test func atlasRejectsANonPositiveScale() async throws {
        try await expectAtlasInvalidParams(["scale": .double(0)])
    }

    @Test func atlasRejectsAnOutOfRangeNodeLimit() async throws {
        try await expectAtlasInvalidParams(["maxNodes": .int(0)])
    }

    private func expectAtlasInvalidParams(_ arguments: [String: Value]) async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("atlas.pdf")
            let error = await #expect(throws: MCPError.self) {
                _ = try await MCPTestSupport.testRegistry.call(
                    name: "acai_atlas",
                    arguments: ["path": .string(dir.path), "output": .string(output.path)]
                        .merging(arguments) { _, new in new })
            }
            guard case .invalidParams = error else {
                Issue.record("expected invalidParams, got \(String(describing: error))")
                return
            }
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }
    #endif
}
