import UMLCore
import UMLQuality

// UMLQualityTests builds small artifacts by hand and enriches them with a representative
// classification, mirroring UMLCoreTests' fixture. Production always injects a real language
// configuration; tests opt into this one explicitly.
extension CodeArtifact.SourceLanguage {
    static let swift = CodeArtifact.SourceLanguage(rawValue: "swift")
}

extension LanguageConfiguration {
    static let test = LanguageConfiguration(
        primitiveTypeNames: ["Void", "String", "Int", "Double", "Bool", "Optional"],
        collectionTypeNames: ["Array", "Set", "Dictionary", "List", "Map"],
        annotationStereotypes: ["entity": "entity", "repository": "repository"]
    )
}

extension CodeArtifact {
    func enriched() -> CodeArtifact { enriched(configuration: .test) }
}

// Test-only convenience initializers keeping the pre-resolver `annotationStereotypes` ergonomics: the
// production APIs now require a `LanguageConfigurationResolver` (no empty default), but these fixtures
// analyse a single hand-built language, so a single-language resolver over the given stereotypes is the
// faithful equivalent.
extension QualityEvaluator {
    init(
        rules: QualityRules,
        moduleResolver: ModuleResolver = .standard,
        annotationStereotypes: [String: String] = [:]
    ) {
        self.init(
            rules: rules, moduleResolver: moduleResolver,
            languageResolver: LanguageConfigurationResolver(
                single: LanguageConfiguration(annotationStereotypes: annotationStereotypes)))
    }
}

extension TypeQuery {
    init(
        artifact: CodeArtifact,
        selector: Selector = Selector(),
        members: MemberFilter = MemberFilter(),
        moduleResolver: ModuleResolver = .standard,
        annotationStereotypes: [String: String] = [:]
    ) {
        self.init(
            artifact: artifact, selector: selector, members: members, moduleResolver: moduleResolver,
            languageResolver: LanguageConfigurationResolver(
                single: LanguageConfiguration(annotationStereotypes: annotationStereotypes)))
    }
}
