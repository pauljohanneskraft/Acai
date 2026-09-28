import Foundation
import MCP
import Testing
import AcaiLibrary
@testable import AcaiMCP

/// Covers the tools that brought the MCP to parity with the CLI: diff, callgraph cycles mode, inspect
/// enums mode, diagram, (macOS) image, and `acai_quality`'s baseline / movement verification.
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

    @Test func qualityRejectsMovementsWithoutABaseline() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let rules = try movementRules(in: dir)
            let error = await #expect(throws: MCPError.self) {
                _ = try await MCPTestSupport.call(
                    "acai_quality", on: MCPTestSupport.testRegistry, path: dir, ["rules": .string(rules.path)])
            }
            // An unreadable rules file also throws `invalidParams`.
            #expect("\(try #require(error))".contains("'baseline'"))
        }
    }

    @Test func qualityWithoutABaselineOmitsDrift() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call(
                "acai_quality", on: MCPTestSupport.testRegistry, path: dir)
            let object = try #require(value.objectValue)
            #expect(object["quality"] != nil)
            #expect(object["drift"] == nil)
        }
    }

    @Test func qualityWithABaselineReportsAMovementInTheWrongDirection() async throws {
        try await MCPTestSupport.withTempDirectory { baseline in
            try await MCPTestSupport.withTempDirectory { head in
                try MCPTestSupport.writeSampleSwiftSource(in: baseline)
                try MCPTestSupport.writeSampleSwiftSource(in: head)
                try addCollaborator(to: head)
                let rules = try movementRules(in: head)
                let value = try await MCPTestSupport.call(
                    "acai_quality", on: MCPTestSupport.testRegistry, path: head,
                    ["rules": .string(rules.path), "baseline": .string(baseline.path)])
                let object = try #require(value.objectValue)
                #expect(object["drift"]?.objectValue != nil)

                let violations = try #require(object["quality"]?.objectValue?["violations"]?.arrayValue)
                let movement = try #require(violations.first {
                    $0.objectValue?["ruleKind"]?.stringValue == "movement"
                        && $0.objectValue?["subject"]?.stringValue == "Service"
                }?.objectValue)
                let detail = try #require(movement["detail"]?.objectValue)
                #expect(detail["metric"]?.stringValue == "fanOut")
                let before = try #require(detail["before"]?.stringValue.flatMap(Double.init))
                let after = try #require(detail["after"]?.stringValue.flatMap(Double.init))
                #expect(after > before)
            }
        }
    }

    @Test func qualityRejectsTheAnalyzedPathAsItsOwnBaseline() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let rules = try movementRules(in: dir)
            let error = await #expect(throws: MCPError.self) {
                _ = try await MCPTestSupport.call(
                    "acai_quality", on: MCPTestSupport.testRegistry, path: dir,
                    ["rules": .string(rules.path), "baseline": .string(dir.path + "/.")])
            }
            #expect("\(try #require(error))".contains("the analyzed path itself"))
        }
    }

    @Test func qualityAcceptsAJSONArtifactAsTheBaseline() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let artifact = try await AnalysisService.standard.analyzeProject(at: dir, allowedLanguages: [])
            let baseline = dir.appendingPathComponent("baseline.json")
            try JSONEncoder().encode(artifact).write(to: baseline)
            try addCollaborator(to: dir)
            let rules = try movementRules(in: dir)
            let value = try await MCPTestSupport.call(
                "acai_quality", on: MCPTestSupport.testRegistry, path: dir,
                ["rules": .string(rules.path), "baseline": .string(baseline.path)])
            let object = try #require(value.objectValue)
            #expect(object["drift"]?.objectValue != nil)
            let violations = try #require(object["quality"]?.objectValue?["violations"]?.arrayValue)
            #expect(violations.contains { $0.objectValue?["ruleKind"]?.stringValue == "movement" })
        }
    }

    /// No `minImprovement`: the metric must not get worse.
    private func movementRules(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("quality.yml")
        try """
        movements:
          - target: { typeGlob: "Service" }
            metric: fanOut
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func addCollaborator(to directory: URL) throws {
        try """
        class Logger {
            func log() {}
        }

        extension Service {
            func trace(logger: Logger) {
                logger.log()
            }
        }
        """.write(to: directory.appendingPathComponent("Logger.swift"), atomically: true, encoding: .utf8)
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
