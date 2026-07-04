import Testing
import Foundation
import UMLCore
@testable import UMLConformance

/// Covers `SmellScan`: a threshold breach becomes a ranked `smell` `Violation` carrying the metric,
/// value, threshold and a location; a clean type produces nothing; custom thresholds are honoured.
@Suite("Conformance: SmellScan")
struct SmellScanTests {

    private func wideMethodType(_ name: String, parameters: Int) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            members: [
                Member(
                    name: "configure", kind: .method, accessLevel: .public,
                    parameters: (0..<parameters).map { Parameter(internalName: "p\($0)") })
            ],
            location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types)
    }

    @Test func longParameterListBreachesMaxParameters() {
        // Default threshold is maxParameters ≤ 5; a 7-parameter method breaches it.
        let findings = SmellScan(artifact: artifact([wideMethodType("Wide", parameters: 7)])).findings
        let smell = findings.first { $0.detail["metric"] == "maxParameters" }
        #expect(smell != nil)
        #expect(smell?.ruleKind == "smell")
        #expect(smell?.subject == "Wide")
        #expect(smell?.source?.filePath == "Wide.swift")
        #expect(smell?.detail["value"] == "7")
        #expect(smell?.detail["threshold"] == "5")
    }

    @Test func cleanTypeProducesNoFindings() {
        let findings = SmellScan(artifact: artifact([wideMethodType("Narrow", parameters: 2)])).findings
        #expect(findings.isEmpty)
    }

    @Test func rankedMostSevereFirst() {
        let findings = SmellScan(
            artifact: artifact([wideMethodType("A", parameters: 7), wideMethodType("B", parameters: 12)]),
            thresholds: [MetricBudget(metric: .maxParameters, max: 5)]).findings
        // B overshoots the threshold more, so it ranks ahead of A.
        #expect(findings.map(\.subject) == ["B", "A"])
    }
}
