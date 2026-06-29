import Testing
import UMLCore
@testable import UMLConformance

@Suite("Conformance: Evaluator")
struct ConformanceEvaluatorTests {

    private func type(
        _ name: String, kind: TypeKind = .class, module: String = "App",
        access: AccessLevel = .internal, annotations: [String] = [], members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, accessLevel: access,
            members: members, annotations: annotations,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship] = []) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: rels).enriched()
    }

    // MARK: Forbidden dependencies

    @Test func forbiddenDependencyIsFlagged() {
        let art = artifact(
            [type("Service", module: "Core"), type("Database", module: "Infra")],
            [Relationship(kind: .dependency, source: "Service", target: "Database")])
        let rules = ConformanceRules(forbidden: [
            DependencyRule(from: Selector(module: "Core"), to: Selector(module: "Infra"))
        ])
        let report = ConformanceEvaluator(rules: rules).evaluate(art)
        #expect(report.violations.count == 1)
        #expect(report.violations.first?.ruleKind == "forbidden-dependency")
        #expect(report.violations.first?.source?.filePath == "Sources/Core/Service.swift")
        #expect(!report.isPassing)
    }

    @Test func allowedDependencyDoesNotTrip() {
        let art = artifact(
            [type("Service", module: "Core"), type("Helper", module: "Core")],
            [Relationship(kind: .dependency, source: "Service", target: "Helper")])
        let rules = ConformanceRules(forbidden: [
            DependencyRule(from: Selector(module: "Core"), to: Selector(module: "Infra"))
        ])
        let report = ConformanceEvaluator(rules: rules).evaluate(art)
        #expect(report.isPassing)
        #expect(report.checkedRuleCount == 1)
    }

    @Test func forbiddenRuleRespectsEdgeKindFilter() {
        let art = artifact(
            [type("A"), type("B")],
            [Relationship(kind: .dependency, source: "A", target: "B")])
        // Only inheritance is forbidden; the actual edge is a dependency → no violation.
        let rules = ConformanceRules(forbidden: [
            DependencyRule(from: Selector(typeGlob: "A"), to: Selector(typeGlob: "B"), kinds: [.inheritance])
        ])
        #expect(ConformanceEvaluator(rules: rules).evaluate(art).isPassing)
    }

    @Test func stereotypeSelectorMatchesAnnotation() {
        let art = artifact(
            [type("UserRepo", module: "Data", annotations: ["@Repository"]),
             type("Logger", module: "Core")],
            [Relationship(kind: .dependency, source: "Logger", target: "UserRepo")])
        // Logger (no stereotype) must not depend on a @Repository.
        let rules = ConformanceRules(forbidden: [
            DependencyRule(from: Selector(), to: Selector(stereotype: "repository"))
        ])
        let report = ConformanceEvaluator(
            rules: rules, annotationStereotypes: ["repository": "repository"]
        ).evaluate(art)
        #expect(report.violations.contains { $0.subject == "Logger→UserRepo" })
    }

    // MARK: Cycles

    @Test func moduleCycleIsDetected() {
        // Core → Infra and Infra → Core : a two-module cycle.
        let art = artifact(
            [type("A", module: "Core"), type("B", module: "Infra")],
            [Relationship(kind: .dependency, source: "A", target: "B"),
             Relationship(kind: .dependency, source: "B", target: "A")])
        let rules = ConformanceRules(cycles: CycleRule(scope: .modules))
        let report = ConformanceEvaluator(rules: rules).evaluate(art)
        #expect(report.violations.contains { $0.ruleKind == "cycle" })
    }

    @Test func acyclicModulesPass() {
        let art = artifact(
            [type("A", module: "Core"), type("B", module: "Infra")],
            [Relationship(kind: .dependency, source: "A", target: "B")])
        let rules = ConformanceRules(cycles: CycleRule(scope: .modules))
        #expect(ConformanceEvaluator(rules: rules).evaluate(art).isPassing)
    }

    // MARK: Budgets

    @Test func moduleDistanceBudgetBreachIsFlagged() {
        // A single concrete module nothing depends on → instability 0, abstractness 0 → distance 1.
        let art = artifact([type("A", module: "App"), type("B", module: "App")])
        let rules = ConformanceRules(budgets: [
            MetricBudget(target: Selector(module: "*"), metric: .distance, max: 0.5)
        ])
        let report = ConformanceEvaluator(rules: rules).evaluate(art)
        #expect(report.violations.contains { $0.ruleKind == "budget" && $0.subject == "App" })
    }

    @Test func typeFanOutBudgetBreachIsFlagged() {
        let art = artifact(
            [type("Hub"), type("X"), type("Y")],
            [Relationship(kind: .dependency, source: "Hub", target: "X"),
             Relationship(kind: .dependency, source: "Hub", target: "Y")])
        let rules = ConformanceRules(budgets: [
            MetricBudget(target: Selector(typeGlob: "Hub"), metric: .fanOut, max: 1)
        ])
        let report = ConformanceEvaluator(rules: rules).evaluate(art)
        let breach = report.violations.first { $0.subject == "Hub" }
        #expect(breach?.ruleKind == "budget")
        #expect(breach?.detail["metric"] == "fanOut")
    }

    @Test func budgetWithinBoundsPasses() {
        let art = artifact([type("A"), type("B")],
                           [Relationship(kind: .dependency, source: "A", target: "B")])
        let rules = ConformanceRules(budgets: [
            MetricBudget(target: Selector(typeGlob: "*"), metric: .fanOut, max: 5)
        ])
        #expect(ConformanceEvaluator(rules: rules).evaluate(art).isPassing)
    }
}

@Suite("Conformance: Glob")
struct GlobTests {
    @Test func matchesWildcards() {
        #expect(Glob("*").matches("anything"))
        #expect(Glob("App.*").matches("App.Service"))
        #expect(Glob("*Service").matches("OrderService"))
        #expect(Glob("User?").matches("Users"))
        #expect(!Glob("App.*").matches("Core.Service"))
        #expect(!Glob("Exact").matches("Exactly"))
        #expect(Glob("Exact").matches("Exact"))
    }
}
