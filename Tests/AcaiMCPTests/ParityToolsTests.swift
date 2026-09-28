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

    /// Dart is the fixture language because its `LanguageConfiguration` carries a
    /// `generatedCodeFilter` (`.g.dart` and friends); Swift's does not.
    private func writeDartSide(in directory: URL, generatedTypes: [String]) throws {
        try "class Model {}\n".write(
            to: directory.appendingPathComponent("model.dart"), atomically: true, encoding: .utf8)
        try generatedTypes.map { "class \($0) {}" }.joined(separator: "\n").write(
            to: directory.appendingPathComponent("model.g.dart"), atomically: true, encoding: .utf8)
    }

    private func diffedTypeIDs(includeGenerated: Bool?) async throws -> (added: [String], removed: [String]) {
        try await MCPTestSupport.withTempDirectory { old in
            try await MCPTestSupport.withTempDirectory { new in
                try writeDartSide(in: old, generatedTypes: ["ModelAdapter"])
                try writeDartSide(in: new, generatedTypes: ["ModelAdapter", "ExtraAdapter"])
                var arguments: [String: Value] = [
                    "pathOld": .string(old.path), "pathNew": .string(new.path)
                ]
                if let includeGenerated {
                    arguments["includeGenerated"] = .bool(includeGenerated)
                }
                let result = try await MCPTestSupport.testRegistry.call(name: "acai_diff", arguments: arguments)
                let diff = try #require(result.structuredContent?.objectValue?["diff"]?.objectValue)
                func ids(_ key: String) -> [String] {
                    (diff[key]?.arrayValue ?? [])
                        .compactMap { $0.objectValue?["id"]?.stringValue ?? $0.stringValue }
                }
                return (ids("addedTypes"), ids("removedTypes"))
            }
        }
    }

    @Test func diffExcludesGeneratedTypesByDefault() async throws {
        let (added, removed) = try await diffedTypeIDs(includeGenerated: nil)
        #expect(!added.contains { $0.contains("ExtraAdapter") })
        #expect(!added.contains { $0.contains("ModelAdapter") })
        #expect(!removed.contains { $0.contains("ModelAdapter") })
    }

    @Test func diffIncludesGeneratedTypesWhenOptedIn() async throws {
        let (added, _) = try await diffedTypeIDs(includeGenerated: true)
        #expect(added.contains { $0.contains("ExtraAdapter") })
    }

    @Test func diffSchemaDeclaresIncludeGenerated() throws {
        let tool = try #require(ToolRegistry.standard.tools.first { $0.name == "acai_diff" })
        let properties = try #require(tool.inputSchema.objectValue?["properties"]?.objectValue)
        #expect(properties["includeGenerated"]?.objectValue?["type"]?.stringValue == "boolean")
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
    #endif
}
