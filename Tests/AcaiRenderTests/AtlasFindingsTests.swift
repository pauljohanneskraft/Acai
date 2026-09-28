import Foundation
import Testing
@testable import AcaiCore
@testable import AcaiDiagram
@testable import AcaiQuality
@testable import AcaiRender

@Suite("Atlas Findings")
struct AtlasFindingsTests {

    private func location(_ line: Int) -> AcaiCore.SourceLocation {
        AcaiCore.SourceLocation(filePath: "Widget.swift", line: line, column: 1)
    }

    private func findings(
        violations: [Violation] = [],
        candidates: [DeadCodeScan.Candidate] = [],
        coverage: CallGraph.Coverage = .init(resolved: 1, total: 1),
        diagnostics: [ParseDiagnostic] = []
    ) -> [AtlasFinding] {
        AtlasFindings(
            quality: QualityReport(violations: violations, checkedRuleCount: violations.count),
            deadCode: .init(coverage: coverage, candidates: candidates),
            health: .init(
                score: 1, typeCount: 1, diagnosticCount: diagnostics.count, countsByKind: [:],
                diagnostics: diagnostics)
        ).findings
    }

    @Test func aDependencyCycleOutranksAnOrdinaryRuleBreach() {
        let results = findings(violations: [
            Violation(ruleKind: "budget", message: "Too wide.", subject: "Widget"),
            Violation(ruleKind: "cycle", message: "types dependency cycle: A → B → A.", subject: "A,B")
        ])
        #expect(results.map(\.severity) == [.warning, .critical])
        #expect(results.allSatisfy { $0.kind == .violation })
    }

    @Test func deadCodeCarriesTheCoverageCaveat() throws {
        let results = findings(
            candidates: [.init(id: "Widget.unused", location: location(7))],
            coverage: .init(resolved: 3, total: 4))
        let finding = try #require(results.first)
        #expect(finding.severity == .info)
        #expect(finding.kind == .deadCode)
        #expect(finding.message.contains("75%"))
    }

    @Test func aParseErrorIsCriticalAndARecoveryIsNot() {
        let results = findings(diagnostics: [
            ParseDiagnostic(location: location(1), kind: .error, message: "Unexpected token."),
            ParseDiagnostic(location: location(2), kind: .missing, message: "Missing '}'.")
        ])
        #expect(results.map(\.severity) == [.critical, .warning])
        #expect(results.allSatisfy { $0.kind == .health })
    }

    @Test func eachLensContributesInOrder() {
        let results = findings(
            violations: [Violation(ruleKind: "budget", message: "Too wide.", subject: "Widget")],
            candidates: [.init(id: "Widget.unused", location: nil)],
            diagnostics: [ParseDiagnostic(location: location(1), kind: .error, message: "Unexpected token.")])
        #expect(results.map(\.kind) == [.violation, .deadCode, .health])
    }

    @Test func theExportedLineNamesSeverityLensSubjectAndLocation() {
        let finding = AtlasFinding(
            kind: .violation, severity: .critical, title: "Widget", message: "Too wide.",
            location: location(12))
        #expect(finding.line == "[Critical] Quality Violation — Widget: Too wide. (Widget.swift:12)")
    }

    @Test func aFindingWithNoLocationOmitsTheSuffix() {
        let finding = AtlasFinding(
            kind: .deadCode, severity: .info, title: "Widget.unused", message: "No caller.", location: nil)
        #expect(finding.line == "[Info] Dead Code — Widget.unused: No caller.")
    }
}
