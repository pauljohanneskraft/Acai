import Foundation
import Testing
import AcaiCore
@testable import AcaiQuality

/// A `Selector` can only include, so a tight budget had to be loosened to its worst case to let a
/// known exception through. `exclude` carves that exception out instead.
@Suite("Quality: Selector exclusions")
struct SelectorExclusionTests {

    private func type(_ name: String, module: String = "App", members: [Member] = []) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .internal,
            members: members, location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    private func method(_ name: String) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal)
    }

    /// Two classes with the same method count, one of them named as an accepted exception.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                type("Visitor", members: (1...6).map { method("visit\($0)") }),
                type("Service", members: (1...6).map { method("run\($0)") })
            ]
        ).enriched()
    }

    private func budget(exclude: [Selector]?) -> QualityRules {
        QualityRules(budgets: [
            MetricBudget(target: Selector(kind: .class, exclude: exclude), metric: .weightedMethods, max: 3)
        ])
    }

    @Test func excludedTypeOverBudgetProducesNoViolation() {
        let report = QualityEvaluator(rules: budget(exclude: [Selector(typeGlob: "Visitor")])).evaluate(artifact())
        #expect(report.violations.map(\.subject) == ["Service"])
    }

    @Test func withoutTheExclusionBothBreach() {
        let report = QualityEvaluator(rules: budget(exclude: nil)).evaluate(artifact())
        #expect(Set(report.violations.map(\.subject)) == ["Service", "Visitor"])
    }

    @Test func exclusionFacetsAreAndCombinedLikeAnyOtherSelector() {
        // The carve-out names a module the type isn't in, so it doesn't apply.
        let exclude = [Selector(module: "Other", typeGlob: "Visitor")]
        let report = QualityEvaluator(rules: budget(exclude: exclude)).evaluate(artifact())
        #expect(Set(report.violations.map(\.subject)) == ["Service", "Visitor"])
    }

    @Test func aGlobExclusionCarvesOutAFamilyOfTypes() {
        let report = QualityEvaluator(rules: budget(exclude: [Selector(typeGlob: "*vice")])).evaluate(artifact())
        #expect(report.violations.map(\.subject) == ["Visitor"])
    }

    @Test func moduleBudgetHonoursAModuleNamedExclusion() {
        let art = CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [type("A", module: "Core"), type("B", module: "Infra")]
        ).enriched()
        // Both modules are concrete and depended on by nothing, so both sit at distance 1.
        let rules = QualityRules(budgets: [
            MetricBudget(target: Selector(exclude: [Selector(module: "Infra")]), metric: .distance, max: 0.5)
        ])
        #expect(QualityEvaluator(rules: rules).evaluate(art).violations.map(\.subject) == ["Core"])
    }

    /// A module-scope check reads only the module facets, and a facet-less selector matches every
    /// module — so a type-only carve-out must be ignored there rather than exempt the codebase.
    @Test func moduleBudgetIgnoresATypeOnlyExclusion() {
        let art = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [type("A", module: "Core")]
        ).enriched()
        let rules = QualityRules(budgets: [
            MetricBudget(target: Selector(exclude: [Selector(typeGlob: "A")]), metric: .distance, max: 0.5)
        ])
        #expect(QualityEvaluator(rules: rules).evaluate(art).violations.map(\.subject) == ["Core"])
    }

    @Test func nameOnlyMatchingIgnoresAModuleOnlyExclusion() {
        let selector = Selector(exclude: [Selector(module: "Core")])
        #expect(selector.matchesName("Idle"))
        #expect(!Selector(exclude: [Selector(typeGlob: "Idle")]).matchesName("Idle"))
    }

    @Test func exclusionsSurviveACodableRoundTrip() throws {
        let selector = Selector(kind: .class, exclude: [Selector(typeGlob: "Visitor")])
        let data = try JSONEncoder().encode(selector)
        #expect(try JSONDecoder().decode(Selector.self, from: data) == selector)
    }
}
