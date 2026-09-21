import Testing
import AcaiCore
@testable import AcaiQuality

// AcaiQualityTests builds small artifacts by hand; sourceLanguage is stamped directly on each
// fixture type (rather than going through `enriched(using:)`) since these tests only need it for
// `StarterQualityRules`' per-language grouping, not for a real multi-language resolver.
private extension CodeArtifact.SourceLanguage {
    static let c = CodeArtifact.SourceLanguage(rawValue: "c")
}

@Suite("Quality: Starter rules")
struct StarterQualityRulesTests {

    private func type(
        _ name: String, module: String = "App", language: CodeArtifact.SourceLanguage? = nil,
        members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .internal,
            members: members,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1),
            sourceLanguage: language)
    }

    private func publicStoredProperty(_ name: String) -> Member {
        Member(name: name, kind: .property, accessLevel: .public)
    }

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types, relationships: []).enriched()
    }

    private func graph(_ types: [TypeDeclaration]) -> GraphView {
        GraphView(
            artifact: artifact(types),
            languageResolver: LanguageConfigurationResolver(single: .test))
    }

    @Test func singleLanguageArtifactSeedsOneUnscopedHint() {
        let types = [
            type("Config", language: .swift, members: [publicStoredProperty("a"), publicStoredProperty("b")])
        ]
        let yaml = StarterQualityRules(graph: graph(types)).yaml
        #expect(yaml.contains("#  - metric: mutablePublicState   # publicly settable stored properties"))
        #expect(yaml.contains("#    max: 2   # max seen: 2"))
        #expect(!yaml.contains("target: { language:"))
    }

    @Test func polyglotArtifactSeedsOneHintPerLanguageNotDominatedByTheOther() {
        // Every C struct field reads `.public` (C has no access control), so a naive global maximum
        // would be set by `CHeader`'s three fields — meaningless as a ceiling for `Service`, which
        // has exactly one real encapsulation leak.
        let types = [
            type("CHeader", language: .c, members: [
                publicStoredProperty("a"), publicStoredProperty("b"), publicStoredProperty("c")
            ]),
            type("Service", language: .swift, members: [publicStoredProperty("leak")])
        ]
        let yaml = StarterQualityRules(graph: graph(types)).yaml

        #expect(yaml.contains("#    target: { language: c }"))
        #expect(yaml.contains("#    target: { language: swift }"))

        let lines = yaml.split(separator: "\n").map(String.init)
        func maxLine(after targetLine: String) -> String? {
            guard let index = lines.firstIndex(of: targetLine) else { return nil }
            return lines[index...].first { $0.contains("max:") }
        }
        #expect(maxLine(after: "#    target: { language: c }") == "#    max: 3   # max seen: 3")
        #expect(maxLine(after: "#    target: { language: swift }") == "#    max: 1   # max seen: 1")
    }

    @Test func languageSelectorScopesABudgetToOneLanguage() {
        let art = artifact([
            type("CHeader", language: .c, members: [publicStoredProperty("a")]),
            type("Service", language: .swift, members: [publicStoredProperty("leak")])
        ])
        let rules = QualityRules(budgets: [
            MetricBudget(target: Selector(language: .swift), metric: .mutablePublicState, max: 0)
        ])
        let report = QualityEvaluator(rules: rules).evaluate(art)
        #expect(report.violations.count == 1)
        #expect(report.violations.first?.subject == "Service")
    }
}
