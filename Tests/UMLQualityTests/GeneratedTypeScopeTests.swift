import Foundation
import Testing
import UMLCore
import UMLQuality

/// `QualityRules.includeGeneratedTypes` controls whether machine-generated types are analysed. Default
/// (`false`) drops them before evaluation, matching the CLI's `--include-generated` default and the
/// app's statistics pane, so every surface reports the same numbers.
@Suite("Quality: generated-type scope")
struct GeneratedTypeScopeTests {

    /// A language whose generated-code filter marks `*.g.swift` files as generated.
    private var resolver: LanguageConfigurationResolver {
        LanguageConfigurationResolver(single: LanguageConfiguration(
            generatedCodeFilter: GeneratedCodeFilter(
                displayName: "Test Generated", explanation: "", fileSuffixes: [".g.swift"])))
    }

    /// One hand-written type and one generated type, each with a property.
    private func artifact() -> CodeArtifact {
        func type(_ name: String, file: String) -> TypeDeclaration {
            TypeDeclaration(
                id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
                members: [Member(name: "value", kind: .property, accessLevel: .internal)],
                location: SourceLocation(filePath: file, line: 1, column: 1))
        }
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [type("Real", file: "Sources/App/Real.swift"),
                    type("Gen", file: "Sources/App/Model.g.swift")])
    }

    /// A budget every type here breaches (any property is one too many), so each type that survives
    /// filtering shows up as exactly one violation subject.
    private func violationSubjects(includeGenerated: Bool) -> Set<String> {
        let rules = QualityRules(
            budgets: [MetricBudget(metric: .numberOfProperties, max: 0)],
            includeGeneratedTypes: includeGenerated)
        let report = QualityEvaluator(rules: rules, languageResolver: resolver).evaluate(artifact())
        return Set(report.violations.map(\.subject))
    }

    @Test func excludesGeneratedTypesByDefault() {
        #expect(violationSubjects(includeGenerated: false) == ["Real"])
    }

    @Test func includesGeneratedTypesWhenOptedIn() {
        #expect(violationSubjects(includeGenerated: true) == ["Real", "Gen"])
    }

    @Test func rulesDecodeIncludeGeneratedTypesDefaultingToFalse() throws {
        let decoder = JSONDecoder()
        let bare = try decoder.decode(QualityRules.self, from: Data("{}".utf8))
        #expect(bare.includeGeneratedTypes == false)
        let opted = try decoder.decode(
            QualityRules.self, from: Data(#"{"includeGeneratedTypes": true}"#.utf8))
        #expect(opted.includeGeneratedTypes == true)
    }
}
