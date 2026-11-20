import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// The other half of the maintainer's premise. The per-language goldens pin that *this* language keeps
/// producing what it produced yesterday; nothing pinned that the *same construct* produces the *same
/// `CodeArtifact` shape* in every language — so a C++ class that lost its constructors, or a Dart
/// parameter that lost its type, stayed green everywhere.
///
/// Each feature is one hand-written expected shape and one idiomatic snippet per language. A language
/// that spells one field of the feature differently carries an allowance in the expectation; only a
/// language that genuinely cannot express the feature at all carries a `.waiver` with the reason.
/// Anything else has to normalise to the same shape. `ContractNormalizer` documents every difference
/// it is allowed to erase.
@Suite("Language feature matrix")
struct LanguageFeatureMatrixTests {

    static let corpus = ContractFeatureCorpus()
    static let cases: [(feature: String, language: ContractFeatureCorpus.Language)] =
        corpus.features.flatMap { feature in corpus.languages.map { (feature, $0) } }

    @Test("the same construct yields the same shape in every language", arguments: cases)
    func matchesExpectedShape(feature: String, language: ContractFeatureCorpus.Language) throws {
        let corpus = Self.corpus
        if let reason = try corpus.waiver(feature: feature, language: language) {
            // The waiver file is the record of *why*; it only has to be the language's sole answer.
            #expect(
                !FileManager.default.fileExists(
                    atPath: corpus.snippetURL(feature: feature, language: language).path),
                "\(feature)/\(language.stem) has both a snippet and a waiver (\(reason)) — delete the waiver")
            return
        }
        let actual = try corpus.shape(feature: feature, language: language)
        guard let expectation = try? corpus.expectation(feature: feature) else {
            // Reported with the shape in hand, since authoring the expectation is the next step.
            throw ContractFeatureCorpus.Failure.missingExpectation(
                feature: feature,
                path: "Tests/AcaiContractTests/Features/\(feature).expected.json; "
                    + "\(language.stem) currently produces:\n\(actual.json)")
        }
        let allowance = expectation.allowance(for: language)
        let compared = allowance.actual(actual)
        let expected = allowance.expected(expectation.shape)
        #expect(
            compared == expected,
            """
            \(feature) in \(language.stem) does not normalise to the expected shape.

            expected:
            \(expected.json)

            actual:
            \(compared.json)
            """
        )
    }

    /// A feature directory with no expectation, or with no language at all, would pass the matrix above
    /// while proving nothing.
    @Test("every feature has an expectation and covers every language")
    func everyFeatureIsComplete() throws {
        let corpus = Self.corpus
        #expect(!corpus.features.isEmpty, "the feature corpus is empty")
        for feature in corpus.features {
            _ = try corpus.expectation(feature: feature)
            let covered = try corpus.languages.filter { language in
                try corpus.waiver(feature: feature, language: language) == nil
            }
            #expect(!covered.isEmpty, "'\(feature)' is waived for every language, so it proves nothing")
        }
    }

    /// A waiver's reason is the only prose in the corpus, and the Kotlin `static-member` waiver spent
    /// its life pointing at a `companion-extension` feature that never existed. A reference that does
    /// not resolve sends the next reader looking for coverage that is not there.
    @Test("every feature a waiver cites exists")
    func waiverReferencesResolve() throws {
        let corpus = Self.corpus
        let features = Set(corpus.features)
        for feature in corpus.features {
            for language in corpus.languages {
                guard let reason = try corpus.waiver(feature: feature, language: language) else { continue }
                for cited in corpus.citedFeatures(in: reason) where !features.contains(cited) {
                    throw ContractFeatureCorpus.Failure.unknownFeatureReference(
                        feature: feature, language: language.stem,
                        path: "Tests/AcaiContractTests/Features/\(feature)/\(language.stem).waiver",
                        reference: cited)
                }
            }
        }
    }

    /// An allowance for a language that is waived, or for a stem no language uses, relaxes nothing —
    /// it just reads as coverage the matrix does not actually have.
    @Test("every allowance belongs to a language that provides a snippet")
    func allowancesBelongToCoveredLanguages() throws {
        let corpus = Self.corpus
        let stems = Set(corpus.languages.map(\.stem))
        for feature in corpus.features {
            let expectation = try corpus.expectation(feature: feature)
            for (stem, allowance) in expectation.languages {
                #expect(stems.contains(stem), "'\(feature)' allows '\(stem)', which is not a language")
                #expect(!allowance.isEmpty, "'\(feature)' gives '\(stem)' an empty allowance — delete it")
                guard let language = corpus.languages.first(where: { $0.stem == stem }) else { continue }
                let waiver = try corpus.waiver(feature: feature, language: language)
                #expect(
                    waiver == nil,
                    """
                    '\(feature)' both waives and allows '\(stem)' — an allowance only applies to a \
                    language that provides a snippet
                    """)
            }
        }
    }
}
