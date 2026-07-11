import Foundation
import MCP
import Testing
@testable import UMLLibrary
@testable import UMLMCP

/// Covers each tool's output: that it wraps the same engine value the CLI exposes (1:1) and that rows
/// carry `file:line` jump targets. The fixture is Service→Repository, with a deliberately wide method.
@Suite("Analysis Tools")
struct AnalysisToolsTests {

    /// The engine artifact for the fixture, computed directly, to compare tool output against.
    private func engineArtifact(_ dir: URL) throws -> CodeArtifact {
        try AnalysisService.standard.analyzeProject(at: dir, allowedLanguages: [])
    }

    /// A JSON number as a `Double`, whether it round-tripped as an integer (`1`) or a fraction — the
    /// encoder drops the decimal on whole values, so `1.0` decodes back as `Value.int(1)`.
    private func number(_ value: Value?) -> Double? {
        value?.doubleValue ?? value?.intValue.map(Double.init)
    }

    @Test func analyzeReportsCountsMatchingTheEngine() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call("uml_analyze", on: .standard, path: dir)
            let object = try #require(value.objectValue)
            let expected = try engineArtifact(dir)
            #expect(object["typeCount"]?.intValue == expected.flattened().count)
            #expect(object["relationshipCount"]?.intValue == expected.relationships.count)
            #expect(number(object["parseHealthScore"]) == 1)
        }
    }

    @Test func metricsWrapsComputeMetrics() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call("uml_metrics", on: .standard, path: dir)
            let object = try #require(value.objectValue)
            let expected = try engineArtifact(dir).computeMetrics()
            #expect(object["types"]?.arrayValue?.count == expected.types.count)
            #expect(object["modules"] != nil)
        }
    }

    @Test func inspectRowsCarryFileAndLine() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call("uml_inspect", on: .standard, path: dir)
            let rows = try #require(value.objectValue?["items"]?.arrayValue)
            #expect(rows.contains { $0.objectValue?["qualifiedName"]?.stringValue == "Service" })
            let service = try #require(rows.first { $0.objectValue?["qualifiedName"]?.stringValue == "Service" })
            let location = try #require(service.objectValue?["location"]?.objectValue)
            #expect(location["filePath"]?.stringValue?.hasSuffix("Sample.swift") == true)
            #expect(location["line"]?.intValue != nil)
        }
    }

    @Test func impactReportsBlastRadiusWithDependents() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call(
                "uml_impact", on: .standard, path: dir, ["type": .string("Repository")])
            let object = try #require(value.objectValue)
            #expect(object["found"]?.boolValue == true)
            // Service depends on Repository, so it appears in the blast radius.
            #expect((object["blastRadius"]?.intValue ?? 0) >= 1)
        }
    }

    @Test func qualityDefaultBudgetsFlagTheWideParameterList() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            // No rules → the built-in curated smell budgets; the wide method breaches maxParameters.
            let value = try await MCPTestSupport.call("uml_quality", on: .standard, path: dir)
            let findings = try #require(value.objectValue?["violations"]?.arrayValue)
            #expect(findings.contains { ($0.objectValue?["message"]?.stringValue ?? "").contains("maxParameters") })
        }
    }

    @Test func callGraphDeadCodeModeReturnsCandidatesAndCoverage() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call(
                "uml_callgraph", on: .standard, path: dir, ["mode": .string("deadcode")])
            let object = try #require(value.objectValue)
            #expect(object["candidates"]?.arrayValue != nil)
            #expect(object["coverage"] != nil)
        }
    }

    @Test func callGraphMetricsModeReportsNodes() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call("uml_callgraph", on: .standard, path: dir)
            let object = try #require(value.objectValue)
            #expect((object["nodes"]?.arrayValue?.count ?? 0) >= 1)
            #expect(object["coverage"] != nil)
        }
    }

    @Test func qualityExploreListsCycles() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            // Explore mode lists dependency cycles; the fixture is acyclic, but the report is well-formed.
            let value = try await MCPTestSupport.call(
                "uml_quality", on: .standard, path: dir,
                ["explore": .bool(true), "scope": .string("modules")])
            #expect(value.objectValue?["violations"]?.arrayValue != nil)
        }
    }

    @Test func refreshMustBeABooleanNotAString() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            // A stringified `"true"` used to silently read as `false` and serve a stale snapshot.
            await #expect(throws: (any Error).self) {
                _ = try await MCPTestSupport.call(
                    "uml_metrics", on: .standard, path: dir, ["refresh": .string("true")])
            }
        }
    }

    @Test func qualityRejectsAMissingRulesFile() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let missing = dir.appendingPathComponent("does-not-exist.yml")
            await #expect(throws: (any Error).self) {
                _ = try await MCPTestSupport.call(
                    "uml_quality", on: .standard, path: dir, ["rules": .string(missing.path)])
            }
        }
    }

    @Test func analyzeHealthReportsAPerfectScoreForCleanParse() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let value = try await MCPTestSupport.call(
                "uml_analyze", on: .standard, path: dir, ["health": .bool(true)])
            #expect(number(value.objectValue?["score"]) == 1)
        }
    }

    @Test func qualityEvaluatesARulesFile() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            let rules = dir.appendingPathComponent("quality.yml")
            try "budgets: []\n".write(to: rules, atomically: true, encoding: .utf8)
            let value = try await MCPTestSupport.call(
                "uml_quality", on: .standard, path: dir, ["rules": .string(rules.path)])
            #expect(value.objectValue != nil)  // a decodable QualityReport verdict
        }
    }
}
