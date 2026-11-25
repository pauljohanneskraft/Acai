import AcaiCore
import AcaiLibrary

/// What each language is allowed to differ from its source on, and why. Every entry here is a
/// difference the language itself forces; a parser that loses information belongs in a
/// `withKnownIssue` naming its issue, never in this table.
struct SourceFidelityDifferences {
    private let byLanguage: [CodeArtifact.SourceLanguage: DeclaredLanguageDifference]

    init() {
        byLanguage = [
            .swift: DeclaredLanguageDifference(sugarsGenericCollections: true),
            .kotlin: DeclaredLanguageDifference(anonymousNames: [
                .init(
                    suffix: "Companion",
                    keyword: "companion",
                    reason: "an unnamed `companion object` is reported under Kotlin's own default name"
                )
            ]),
            .dart: DeclaredLanguageDifference(anonymousNames: [
                .init(
                    suffix: "Extension",
                    keyword: "extension",
                    reason: "an unnamed `extension on T` is reported as `TExtension`"
                )
            ]),
            .c: cFamily,
            .cpp: cFamily
        ]
    }

    /// `CFamilyTypeReferenceResolver` unwraps the pointer and reference declarators the grammar
    /// nests around a name, so `char *` and `Foo &` both reach the model as the pointee's type.
    private var cFamily: DeclaredLanguageDifference {
        DeclaredLanguageDifference(unmodelledTypeSuffixes: [
            "*": "the declarator's pointer layers are stripped, so a pointer carries the pointee's type",
            "&": "the declarator's reference layers are stripped, so a reference carries the referent's type"
        ])
    }

    /// A language with nothing declared is held to the strict reading, which is where every
    /// language should be.
    func difference(for language: CodeArtifact.SourceLanguage) -> DeclaredLanguageDifference {
        byLanguage[language] ?? DeclaredLanguageDifference()
    }
}
