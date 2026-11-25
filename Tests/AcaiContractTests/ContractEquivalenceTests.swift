import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// Every snippet the feature matrix holds, paired with every variation it has to survive, with the
/// joined snippet's partner already chosen so the suite parses the corpus once rather than once per
/// case.
struct ContractEquivalencePlan {
    struct Case: Sendable, CustomStringConvertible {
        let feature: String
        let language: ContractFeatureCorpus.Language
        let variation: any ContractSourceVariation

        var description: String { "\(feature)/\(language.stem): \(variation.name)" }
    }

    let cases: [Case]
    /// Snippets the join variation cannot reach, because no other snippet in that language declares
    /// names disjoint from theirs.
    let unjoinable: [String]

    init(corpus: ContractFeatureCorpus) {
        var cases: [Case] = []
        var unjoinable: [String] = []
        for feature in corpus.features {
            for language in corpus.languages {
                guard (try? corpus.waiver(feature: feature, language: language)) == nil,
                      (try? corpus.snippet(feature: feature, language: language)) != nil else { continue }
                var variations: [any ContractSourceVariation] =
                    language.parser.fileExtensions.map { ContractUppercaseExtension(fileExtension: $0) }
                variations += [
                    ContractCarriageReturnLineEndings(),
                    ContractLeadingComment(),
                    ContractBlankLinesAndTrailingWhitespace()
                ]
                let partner = ContractDisjointPartner(feature: feature, language: language, corpus: corpus)
                if let partner = try? partner.resolved() {
                    variations += [
                        ContractJoinedSnippet(partner: partner, partnerComesFirst: false),
                        ContractJoinedSnippet(partner: partner, partnerComesFirst: true)
                    ]
                } else {
                    unjoinable.append("\(feature)/\(language.stem)")
                }
                cases += variations.map { Case(feature: feature, language: language, variation: $0) }
            }
        }
        self.cases = cases
        self.unjoinable = unjoinable
    }
}

/// The matrix next door pins that the same construct gives the same *shape* in every language. It says
/// nothing about the same construct written the same way twice: `Widget.H` produced no types where
/// `Widget.h` produced a class (#609) and every snippet stayed green, because no snippet was ever
/// re-read under a different file name, line ending or neighbour.
///
/// Each case takes one snippet, rewrites it in a way that cannot change what it declares, and compares
/// the whole `CodeArtifact` — not the matrix's projection, so a lost end line or call site fails here
/// too. Only the file it was read from is erased, plus what the variation's tolerance names.
@Suite("Equivalent source, equivalent model")
struct ContractEquivalenceTests {

    static let corpus = ContractFeatureCorpus()
    static let plan = ContractEquivalencePlan(corpus: corpus)

    @Test("a rewrite that cannot change what a snippet declares does not change its model",
          arguments: plan.cases)
    func variationPreservesTheArtifact(testCase: ContractEquivalencePlan.Case) throws {
        let corpus = Self.corpus
        let language = testCase.language
        if let reason = testCase.variation.exemption(for: language) {
            #expect(!reason.isEmpty, "\(testCase) is exempt without a reason")
            return
        }
        let snippet = try corpus.snippet(feature: testCase.feature, language: language)
        let original = corpus.artifact(
            source: snippet.source, fileName: snippet.fileName, language: language)
        let varied = testCase.variation.varied(
            ContractSnippet(
                feature: testCase.feature, language: language,
                source: snippet.source, fileName: snippet.fileName))
        let tolerance = testCase.variation.tolerance
        let actual = try ContractArtifactProjection(
            artifact: corpus.artifact(source: varied.source, fileName: varied.fileName, language: language),
            tolerance: tolerance)
        let expected = try ContractArtifactProjection(
            union: [original] + varied.appended, tolerance: tolerance)
        #expect(
            actual == expected,
            """
            \(testCase) does not yield the original's artifact.

            expected:
            \(expected)

            actual:
            \(actual)
            """
        )
    }

    /// A variation that reached no snippet at all would pass by doing nothing.
    @Test("every variation reaches every language that provides a snippet")
    func everyVariationReachesEveryLanguage() throws {
        let corpus = Self.corpus
        let covered = try corpus.languages.filter { language in
            try corpus.features.contains { feature in
                try corpus.waiver(feature: feature, language: language) == nil
            }
        }
        #expect(!covered.isEmpty, "no language provides a snippet")
        for language in covered {
            let names = Set(
                Self.plan.cases
                    .filter { $0.language.stem == language.stem }
                    .map { $0.variation.name })
            #expect(
                names.contains("CRLF line endings"), "\(language.stem) is never checked under CRLF")
            #expect(
                names.contains(where: { $0.hasPrefix("uppercase .") }),
                "\(language.stem) is never checked under an uppercase extension")
            #expect(
                names.contains(where: { $0.hasPrefix("joined ") }),
                """
                no \(language.stem) snippet has a neighbour whose names are disjoint from its own, so \
                the join variation never runs for it
                """)
            for fileExtension in language.parser.fileExtensions {
                #expect(
                    names.contains("uppercase .\(fileExtension.uppercased())"),
                    "\(language.stem) never parses a snippet as .\(fileExtension.uppercased())")
            }
        }
    }

    /// The reason a snippet has no joinable neighbour is a fact about the corpus, not a defect — but it
    /// is one the suite states rather than hides.
    @Test("the snippets the join variation cannot reach are the ones with no disjoint neighbour")
    func unjoinableSnippetsAreAccountedFor() throws {
        let corpus = Self.corpus
        for entry in Self.plan.unjoinable {
            let parts = entry.components(separatedBy: "/")
            guard parts.count == 2, let language = corpus.languages.first(where: { $0.stem == parts[1] })
            else {
                Issue.record("'\(entry)' is not a feature/language pair")
                continue
            }
            let partner = ContractDisjointPartner(feature: parts[0], language: language, corpus: corpus)
            #expect(throws: ContractEquivalenceFailure.self, "\(entry) does have a partner after all") {
                try partner.resolved()
            }
        }
    }
}
