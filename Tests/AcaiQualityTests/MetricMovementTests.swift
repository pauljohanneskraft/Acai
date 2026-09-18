import Foundation
import Testing
import AcaiCore
@testable import AcaiQuality

@Suite("Quality: Metric movements")
struct MetricMovementTests {

    private func type(
        _ name: String, kind: TypeKind = .class, module: String = "App",
        access: AccessLevel = .internal, members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, accessLevel: access,
            members: members,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship] = []) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: rels).enriched()
    }

    // MARK: Explicit movement (type-scoped)

    @Test func explicitMovementSatisfiedPasses() {
        let baseline = artifact(
            [type("Hub"), type("X"), type("Y")],
            [Relationship(kind: .dependency, source: "Hub", target: "X"),
             Relationship(kind: .dependency, source: "Hub", target: "Y")])
        let current = artifact(
            [type("Hub"), type("X")],
            [Relationship(kind: .dependency, source: "Hub", target: "X")])
        let rules = QualityRules(movements: [
            MetricMovement(target: Selector(typeGlob: "Hub"), metric: .fanOut, minImprovement: 1)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        #expect(report.isPassing)
    }

    @Test func explicitMovementShortfallFails() {
        let baseline = artifact(
            [type("Hub"), type("X"), type("Y")],
            [Relationship(kind: .dependency, source: "Hub", target: "X"),
             Relationship(kind: .dependency, source: "Hub", target: "Y")])
        let current = artifact(
            [type("Hub"), type("X")],
            [Relationship(kind: .dependency, source: "Hub", target: "X")])
        let rules = QualityRules(movements: [
            MetricMovement(target: Selector(typeGlob: "Hub"), metric: .fanOut, minImprovement: 2)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        let violation = report.violations.first { $0.ruleKind == "movement" && $0.subject == "Hub" }
        #expect(violation != nil)
        #expect(violation?.detail["metric"] == "fanOut")
        #expect(violation?.detail["before"] == "2")
        #expect(violation?.detail["after"] == "1")
    }

    @Test func regressionWithDefaultMinImprovementIsFlagged() {
        // No minImprovement given → default 0 means "must not get worse"; fanOut got worse.
        let baseline = artifact(
            [type("Hub"), type("X")],
            [Relationship(kind: .dependency, source: "Hub", target: "X")])
        let current = artifact(
            [type("Hub"), type("X"), type("Y")],
            [Relationship(kind: .dependency, source: "Hub", target: "X"),
             Relationship(kind: .dependency, source: "Hub", target: "Y")])
        let rules = QualityRules(movements: [MetricMovement(target: Selector(typeGlob: "Hub"), metric: .fanOut)])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        #expect(report.violations.contains { $0.ruleKind == "movement" && $0.subject == "Hub" })
    }

    @Test func movementsAreSkippedWithoutBaseline() {
        let current = artifact([type("Hub")])
        let rules = QualityRules(movements: [MetricMovement(metric: .fanOut, minImprovement: 5)])
        #expect(QualityEvaluator(rules: rules).evaluate(current).isPassing)
    }

    @Test func newTypeWithNoBaselineValueIsNotEvaluated() {
        // "Hub" doesn't exist in the baseline — nothing to compare, so no violation either way.
        let baseline = artifact([type("Other")])
        let current = artifact([type("Hub"), type("X")], [Relationship(kind: .dependency, source: "Hub", target: "X")])
        let rules = QualityRules(movements: [
            MetricMovement(target: Selector(typeGlob: "Hub"), metric: .fanOut, minImprovement: 3)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        #expect(report.isPassing)
    }

    // MARK: Hidden regression (type-scoped)

    @Test func hiddenRegressionOnUndeclaredTypeMetricIsCaught() {
        // fanOut improves (declared), but numberOfProperties silently regresses on the same type.
        let baseline = artifact(
            [type("Hub", members: [Member(name: "a", kind: .property, accessLevel: .internal)]), type("X"), type("Y")],
            [Relationship(kind: .dependency, source: "Hub", target: "X"),
             Relationship(kind: .dependency, source: "Hub", target: "Y")])
        let current = artifact(
            [type("Hub", members: [
                Member(name: "a", kind: .property, accessLevel: .internal),
                Member(name: "b", kind: .property, accessLevel: .internal),
                Member(name: "c", kind: .property, accessLevel: .internal)
            ]), type("X")],
            [Relationship(kind: .dependency, source: "Hub", target: "X")])
        let rules = QualityRules(movements: [
            MetricMovement(target: Selector(typeGlob: "Hub"), metric: .fanOut, minImprovement: 1)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        #expect(!report.violations.contains { $0.detail["metric"] == "fanOut" })
        let hidden = report.violations.first { $0.detail["metric"] == "numberOfProperties" && $0.subject == "Hub" }
        #expect(hidden != nil)
        #expect(!report.isPassing)
    }

    @Test func untouchedTypesAreNotScannedForHiddenRegressions() {
        // "Other" regresses too, but no movement ever singled it out — it stays out of scope.
        let baseline = artifact([
            type("Hub", members: [Member(name: "a", kind: .property, accessLevel: .internal)]),
            type("Other", members: [Member(name: "a", kind: .property, accessLevel: .internal)])
        ])
        let current = artifact([
            type("Hub", members: [Member(name: "a", kind: .property, accessLevel: .internal)]),
            type("Other", members: [
                Member(name: "a", kind: .property, accessLevel: .internal),
                Member(name: "b", kind: .property, accessLevel: .internal)
            ])
        ])
        let rules = QualityRules(movements: [
            MetricMovement(target: Selector(typeGlob: "Hub"), metric: .numberOfProperties)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        #expect(report.isPassing)
    }

    // MARK: Module-scoped movement

    @Test func moduleMetricMovementIsEvaluated() {
        // Turning A into a protocol raises abstractness, moving distance from 1.0 down to 0.5.
        let baseline = artifact([type("A", kind: .class, module: "App"), type("B", kind: .class, module: "App")])
        let current = artifact([type("A", kind: .protocol, module: "App"), type("B", kind: .class, module: "App")])
        let rules = QualityRules(movements: [
            MetricMovement(target: Selector(module: "App"), metric: .distance, minImprovement: 0.4)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        #expect(report.isPassing)
    }

    @Test func hiddenModuleRegressionOnUndeclaredMetricIsCaught() {
        let baseline = artifact([
            type("A", kind: .class, module: "App", members: [
                Member(name: "run", kind: .method, accessLevel: .public)
            ]),
            type("B", kind: .class, module: "App")
        ])
        let current = artifact([
            type("A", kind: .protocol, module: "App", members: [
                Member(name: "run", kind: .method, accessLevel: .public),
                Member(name: "run2", kind: .method, accessLevel: .public)
            ]),
            type("B", kind: .class, module: "App")
        ])
        let rules = QualityRules(movements: [
            MetricMovement(target: Selector(module: "App"), metric: .distance, minImprovement: 0.1)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(current, baseline: baseline)
        #expect(report.violations.contains { $0.detail["metric"] == "publicApiSurface" && $0.subject == "App" })
    }

    // MARK: Decoding

    @Test func decodesMovementsWithLenientDefaults() throws {
        // Round-trip through the Codable model directly (Yams/YAML is exercised in CLI tests).
        let json = """
        {"movements":[
          {"metric":"fanOut"},
          {"target":{"typeGlob":"Hub"},"metric":"lcom","minImprovement":2,"message":"Hub must get more cohesive"}
        ]}
        """
        let rules = try JSONDecoder().decode(QualityRules.self, from: Data(json.utf8))
        #expect(rules.movements.count == 2)
        #expect(rules.movements[0].target == Selector())
        #expect(rules.movements[0].minImprovement == 0)
        #expect(rules.movements[1].target == Selector(typeGlob: "Hub"))
        #expect(rules.movements[1].minImprovement == 2)
        #expect(rules.movements[1].message == "Hub must get more cohesive")
        #expect(rules.ruleCount == 2)
    }
}
