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

    // MARK: New budget metrics (#103) — each proves its case resolves through the type/module switch.

    private func breaches(_ metric: MetricBudget.Metric, max: Double, on subject: String,
                          in art: CodeArtifact) -> Bool {
        let rules = ConformanceRules(budgets: [MetricBudget(metric: metric, max: max)])
        return ConformanceEvaluator(rules: rules).evaluate(art).violations
            .contains { $0.ruleKind == "budget" && $0.subject == subject && $0.detail["metric"] == metric.rawValue }
    }

    @Test func numberOfPropertiesBudgetBreachIsFlagged() {
        let art = artifact([type("Bag", members: [
            Member(name: "a", kind: .property, accessLevel: .internal),
            Member(name: "b", kind: .property, accessLevel: .internal)
        ])])
        #expect(breaches(.numberOfProperties, max: 1, on: "Bag", in: art))
    }

    @Test func rfcBudgetBreachIsFlagged() {
        let art = artifact([type("Fat", members: [
            Member(name: "a", kind: .method, accessLevel: .internal),
            Member(name: "b", kind: .method, accessLevel: .internal)
        ])])
        #expect(breaches(.rfc, max: 1, on: "Fat", in: art))
    }

    @Test func maxParametersBudgetBreachIsFlagged() {
        let art = artifact([type("Wide", members: [
            Member(name: "call", kind: .method, accessLevel: .internal, parameters: [
                Parameter(internalName: "a", type: TypeReference(name: "Int")),
                Parameter(internalName: "b", type: TypeReference(name: "Int"))
            ])
        ])])
        #expect(breaches(.maxParameters, max: 1, on: "Wide", in: art))
    }

    @Test func mutablePublicStateBudgetBreachIsFlagged() {
        let art = artifact([type("Leaky", access: .public, members: [
            Member(name: "value", kind: .property, accessLevel: .public, type: TypeReference(name: "Int"))
        ])])
        #expect(breaches(.mutablePublicState, max: 0, on: "Leaky", in: art))
    }

    @Test func dataClassScoreBudgetBreachIsFlagged() {
        // One property, no methods → score 1.0 (pure data).
        let art = artifact([type("DTO", members: [
            Member(name: "id", kind: .property, accessLevel: .internal)
        ])])
        #expect(breaches(.dataClassScore, max: 0.5, on: "DTO", in: art))
    }

    @Test func lcomBudgetBreachIsFlagged() {
        // Two methods writing different fields never link → 2 cohesion components.
        func method(_ name: String, writes field: String) -> Member {
            Member(name: name, kind: .method, accessLevel: .internal, assignments: [
                VariableAssignment(targetName: field, op: .assign, value: .init(kind: .expression, text: "0"))
            ])
        }
        let art = artifact([type("Split", members: [method("a", writes: "x"), method("b", writes: "y")])])
        #expect(breaches(.lcom, max: 1, on: "Split", in: art))
    }

    @Test func nestingDepthBudgetBreachIsFlagged() {
        let inner = TypeDeclaration(
            id: "Outer.Inner", name: "Inner", qualifiedName: "Outer.Inner", kind: .struct, accessLevel: .internal,
            location: SourceLocation(filePath: "Sources/App/Outer.swift", line: 2, column: 1))
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .class, accessLevel: .internal,
            nestedTypes: [inner],
            location: SourceLocation(filePath: "Sources/App/Outer.swift", line: 1, column: 1))
        let art = CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [outer]).enriched()
        #expect(breaches(.nestingDepth, max: 0, on: "Outer", in: art))
    }

    @Test func publicApiSurfaceModuleBudgetBreachIsFlagged() {
        let art = artifact([type("API", module: "App", access: .public, members: [
            Member(name: "run", kind: .method, accessLevel: .public)
        ])])
        #expect(breaches(.publicApiSurface, max: 0, on: "App", in: art))
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
