import AcaiCore
import AcaiLibrary

/// What each language is allowed to differ from its source on, and why. Every entry is a difference
/// the language itself forces; a parser that loses information belongs in `KnownParserIssues`
/// naming its issue, never here.
struct SourceFidelityDifferences {
    private let byLanguage: [CodeArtifact.SourceLanguage: DeclaredLanguageDifference]

    init() {
        // `CFamilyTypeReferenceResolver.parseDeclarator` unwraps the pointer and reference
        // declarators the grammar nests around a name, so `char *` reaches the model as `char`.
        let cFamily = DeclaredLanguageDifference(unmodelledTypeSuffixes: [
            "*": "pointer declarators are stripped, so a pointer carries the pointee's type",
            "&": "reference declarators are stripped, so a reference carries the referent's type"
        ])
        byLanguage = [
            .swift: DeclaredLanguageDifference(sugarsGenericCollections: true),
            .kotlin: DeclaredLanguageDifference(substitutedNames: [
                .init(
                    suffix: "Companion",
                    keyword: "companion",
                    reason: "an unnamed `companion object` is reported under Kotlin's own default name"
                ),
                .init(
                    suffix: "init",
                    keyword: "constructor",
                    reason: "a `constructor` is reported as `init`, the name the JVM parsers share"
                )
            ]),
            .dart: DeclaredLanguageDifference(
                substitutedNames: [
                    .init(
                        suffix: "Extension",
                        keyword: "extension",
                        reason: "an unnamed `extension on T` is reported as `TExtension`"
                    )
                ],
                forwardsFieldTypesToConstructorParameters: true
            ),
            .c: cFamily,
            .cpp: cFamily
        ]
    }

    /// A language with nothing declared is held to the strict reading, which is where every language
    /// should be.
    func difference(for language: CodeArtifact.SourceLanguage) -> DeclaredLanguageDifference {
        byLanguage[language] ?? DeclaredLanguageDifference()
    }
}
