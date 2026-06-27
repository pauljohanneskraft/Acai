import Foundation
import Testing
import UMLCore
@testable import UMLConformance

@Suite("Conformance: Layering, type cycles & contracts")
struct ConformancePhase4Tests {

    private func type(
        _ name: String, kind: TypeKind = .class, module: String = "App",
        annotations: [String] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, annotations: annotations,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship] = []) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: rels).enriched()
    }

    private func layers(allowSkip: Bool = true) -> LayerRule {
        LayerRule(layers: [
            LayerRule.Layer(name: "presentation", selector: Selector(module: "UI")),
            LayerRule.Layer(name: "domain", selector: Selector(module: "Domain")),
            LayerRule.Layer(name: "infra", selector: Selector(module: "Infra"))
        ], allowSkip: allowSkip)
    }

    // MARK: Layering

    @Test func downwardDependencyIsAllowed() {
        let art = artifact(
            [type("View", module: "UI"), type("Service", module: "Domain")],
            [Relationship(kind: .dependency, source: "View", target: "Service")])
        let report = ConformanceEvaluator(rules: ConformanceRules(layers: layers())).evaluate(art)
        #expect(report.isPassing)
    }

    @Test func upwardDependencyIsAViolation() {
        // Domain → UI is upward: forbidden.
        let art = artifact(
            [type("View", module: "UI"), type("Service", module: "Domain")],
            [Relationship(kind: .dependency, source: "Service", target: "View")])
        let report = ConformanceEvaluator(rules: ConformanceRules(layers: layers())).evaluate(art)
        #expect(report.violations.contains { $0.ruleKind == "layering" })
    }

    @Test func skippingLayerIsAViolationWhenSkipDisallowed() {
        // UI → Infra skips Domain; allowed when allowSkip, flagged otherwise.
        let art = artifact(
            [type("View", module: "UI"), type("Repo", module: "Infra")],
            [Relationship(kind: .dependency, source: "View", target: "Repo")])
        #expect(ConformanceEvaluator(rules: ConformanceRules(layers: layers(allowSkip: true))).evaluate(art).isPassing)
        let strict = ConformanceEvaluator(rules: ConformanceRules(layers: layers(allowSkip: false))).evaluate(art)
        #expect(strict.violations.contains { $0.ruleKind == "layering" })
    }

    // MARK: Type cycles

    @Test func typeCycleIsDetected() {
        let art = artifact(
            [type("A"), type("B")],
            [Relationship(kind: .dependency, source: "A", target: "B"),
             Relationship(kind: .dependency, source: "B", target: "A")])
        let report = ConformanceEvaluator(rules: ConformanceRules(cycles: CycleRule(scope: .types))).evaluate(art)
        #expect(report.violations.contains { $0.ruleKind == "cycle" && $0.detail["scope"] == "types" })
    }

    @Test func acyclicTypesPass() {
        let art = artifact(
            [type("A"), type("B")],
            [Relationship(kind: .dependency, source: "A", target: "B")])
        #expect(ConformanceEvaluator(rules: ConformanceRules(cycles: CycleRule(scope: .types))).evaluate(art).isPassing)
    }

    // MARK: Stereotype contracts

    @Test func onlyRepositoryMayTouchDatabase() {
        let art = artifact(
            [type("UserRepo", annotations: ["@Repository"]),
             type("Controller"),
             type("Database")],
            [Relationship(kind: .dependency, source: "Controller", target: "Database"),
             Relationship(kind: .dependency, source: "UserRepo", target: "Database")])
        let rules = ConformanceRules(contracts: [
            StereotypeContract(into: Selector(typeGlob: "Database"), only: Selector(stereotype: "repository"))
        ])
        let report = ConformanceEvaluator(
            rules: rules, annotationStereotypes: ["repository": "repository"]
        ).evaluate(art)
        // Controller is flagged; the @Repository is not.
        #expect(report.violations.contains { $0.subject == "Controller→Database" })
        #expect(!report.violations.contains { $0.subject == "UserRepo→Database" })
    }
}

@Suite("Conformance: YAML decoding")
struct ConformanceYAMLTests {
    @Test func decodesAllRuleSections() throws {
        // Round-trip a full rules file through the Codable model (Yams is exercised in CLI tests).
        let json = """
        {"forbidden":[{"from":{"module":"Core"},"to":{"module":"UI"}}],
         "cycles":{"scope":"types"},
         "budgets":[{"metric":"distance","max":0.5}],
         "layers":{"allowSkip":false,"layers":[{"name":"ui","selector":{"module":"UI"}}]},
         "contracts":[{"into":{"typeGlob":"*.Db.*"},"only":{"stereotype":"repository"}}]}
        """
        let rules = try JSONDecoder().decode(ConformanceRules.self, from: Data(json.utf8))
        #expect(rules.forbidden.count == 1)
        #expect(rules.cycles?.scope == .types)
        #expect(rules.budgets.first?.metric == .distance)
        #expect(rules.layers?.allowSkip == false)
        #expect(rules.contracts.count == 1)
        #expect(rules.ruleCount == 5)
    }
}
