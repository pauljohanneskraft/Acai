import Foundation
import MCP
import Testing
import AcaiQuality
@testable import AcaiMCP

@Suite("Quality rules file version")
struct QualityRulesVersionTests {

    @Test("A rules file from a newer Acai is rejected, naming both versions")
    func newerRulesFileIsRejected() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let newer = QualityRules.currentVersion + 1
            let rules = directory.appendingPathComponent("quality.yml")
            try "version: \(newer)\ncycles:\n  scope: modules\n"
                .write(to: rules, atomically: true, encoding: .utf8)

            let error = await #expect(throws: MCPError.self) {
                _ = try await MCPTestSupport.testRegistry.call(
                    name: "acai_quality",
                    arguments: ["path": .string(directory.path), "rules": .string(rules.path)])
            }
            guard case .invalidParams(let detail) = error, let detail else {
                Issue.record("expected invalidParams, got \(String(describing: error))")
                return
            }
            let refusal = UnsupportedRulesVersion(found: newer, supported: QualityRules.currentVersion)
            #expect(detail.contains(refusal.description), "\(detail)")
        }
    }

    @Test("A rules file omitting the version is accepted")
    func rulesFileWithoutTheVersionIsAccepted() async throws {
        try await MCPTestSupport.withTempDirectory { directory in
            try MCPTestSupport.writeSampleSwiftSource(in: directory)
            let rules = directory.appendingPathComponent("quality.yml")
            try "cycles:\n  scope: modules\n".write(to: rules, atomically: true, encoding: .utf8)

            let result = try await MCPTestSupport.testRegistry.call(
                name: "acai_quality",
                arguments: ["path": .string(directory.path), "rules": .string(rules.path)])
            #expect(try #require(result.structuredContent).objectValue?["quality"] != nil)
        }
    }
}
