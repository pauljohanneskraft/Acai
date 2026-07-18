import Testing
import Foundation
import AcaiCore
@testable import AcaiQuality

/// Covers the smells merged into the quality check: evaluating the built-in `QualityRules
/// .defaultQuality` (the curated smell budgets) turns a threshold breach into a `budget` `Violation`
/// carrying the metric, value, a location and a fix hint; a clean type produces nothing; a custom
/// budget set is honoured; and the breaches are ranked worst-first. This is the regression guard that
/// a no-config `quality` run still flags — and ranks — the smells the standalone `smells` command did.
@Suite("Quality: default smell budgets")
struct SmellBudgetTests {

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

    private func findings(
        _ types: [TypeDeclaration], rules: QualityRules = .defaultQuality
    ) -> [Violation] {
        QualityEvaluator(rules: rules).evaluate(artifact(types)).violations
    }

    @Test func longParameterListBreachesMaxParameters() {
        // Default budget is maxParameters ≤ 5; a 7-parameter method breaches it.
        let smell = findings([wideMethodType("Wide", parameters: 7)])
            .first { $0.detail["metric"] == "maxParameters" }
        #expect(smell != nil)
        #expect(smell?.ruleKind == "budget")
        #expect(smell?.subject == "Wide")
        #expect(smell?.source?.filePath == "Wide.swift")
        #expect(smell?.detail["value"] == "7")
        // The breach carries the metric's remediation hint, not just a crossed ceiling.
        #expect(smell?.message.contains("introduce a parameter object") == true)
    }

    @Test func cleanTypeProducesNoFindings() {
        #expect(findings([wideMethodType("Narrow", parameters: 2)]).isEmpty)
    }

    @Test func customBudgetSetIsHonoured() {
        let both = findings(
            [wideMethodType("A", parameters: 7), wideMethodType("B", parameters: 12)],
            rules: QualityRules(budgets: [MetricBudget(metric: .maxParameters, max: 5)]))
        #expect(Set(both.map(\.subject)) == ["A", "B"])
    }

    @Test func rankedMostSevereFirst() {
        // B overshoots the maxParameters budget further than A, so it ranks ahead of A.
        let ranked = findings(
            [wideMethodType("A", parameters: 7), wideMethodType("B", parameters: 12)],
            rules: QualityRules(budgets: [MetricBudget(metric: .maxParameters, max: 5)]))
        #expect(ranked.map(\.subject) == ["B", "A"])
    }
}
