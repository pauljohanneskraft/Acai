import Testing
import AcaiCore
@testable import AcaiQuality

/// `linesOfCode` is budgetable so a rules file can cap outright type size (#330). It is type-scoped
/// and carries no default ceiling — a project declares its own.
@Suite("Quality: lines-of-code budget")
struct LinesOfCodeBudgetTests {

    private func type(_ name: String, lines: Int) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1, endLine: lines))
    }

    private func violations(
        _ types: [TypeDeclaration], max: Double
    ) -> [Violation] {
        QualityEvaluator(rules: QualityRules(budgets: [MetricBudget(metric: .linesOfCode, max: max)]))
            .evaluate(CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types))
            .violations
    }

    @Test func aTypeOverTheCeilingBreachesTheBudget() {
        let breach = violations([type("Sprawling", lines: 400)], max: 200).first
        #expect(breach?.ruleKind == "budget")
        #expect(breach?.subject == "Sprawling")
        #expect(breach?.detail["metric"] == "linesOfCode")
        #expect(breach?.detail["value"] == "400")
        #expect(breach?.source?.filePath == "Sprawling.swift")
        #expect(breach?.message.contains("extract collaborators") == true)
    }

    @Test func aTypeWithinTheCeilingDoesNot() {
        #expect(violations([type("Tidy", lines: 40)], max: 200).isEmpty)
    }

    /// No parser extent means no measurement, so an unmeasured type must not read as a 0-line type
    /// that silently satisfies every ceiling *and* every floor.
    @Test func anUnmeasuredTypeIsNotReportedAgainstAMinimum() {
        let unmeasured = TypeDeclaration(
            id: "Opaque", name: "Opaque", qualifiedName: "Opaque", kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "Opaque.swift", line: 1, column: 1))
        #expect(unmeasured.linesOfCode == 0)
        #expect(violations([unmeasured], max: 200).isEmpty)
    }

    @Test func theMetricIsTypeScoped() {
        #expect(MetricBudget.Metric.linesOfCode.isModuleScoped == false)
        #expect(MetricBudget.Metric.allCases.contains(.linesOfCode))
    }

    /// Not in the built-in defaults: a sensible ceiling is project-specific, so an unasked-for one
    /// would flood any codebase that disagrees.
    @Test func theMetricHasNoDefaultCeiling() {
        #expect(!MetricBudget.defaultSmellBudgets.contains { $0.metric == .linesOfCode })
    }
}
