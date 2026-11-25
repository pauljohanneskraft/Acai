import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// The equivalence suite's own guardrail. Every variation there passes today, so nothing in it proves
/// the comparison can fail — a tolerance that quietly excused the whole artifact, or a variation whose
/// rewrite was a no-op, would look exactly as green.
///
/// Each case takes a real variation of a real snippet, breaks the result the way a parser mishandling
/// that variation would, and requires the comparison to reject it.
@Suite("The equivalence suite can fail")
struct ContractEquivalenceSelfTests {

    static let corpus = ContractFeatureCorpus()
    static let perturbations: [any ContractArtifactPerturbation] = [
        ContractDroppedDeclarations(),
        ContractRenamedFirstDeclaration(),
        ContractShiftedLines(),
        ContractShiftedColumns()
    ]

    static let plan = ContractEquivalencePlan(corpus: corpus)

    /// One case per variation kind per language, so a variation that only ever ran against Swift
    /// cannot look proven.
    static let cases: [ContractEquivalencePlan.Case] = {
        var seen: Set<String> = []
        return plan.cases.filter { seen.insert("\($0.language.stem)/\($0.variation.kind)").inserted }
    }()

    @Test("breaking a variation's result makes the comparison fail", arguments: cases, perturbations)
    func aBrokenVariationIsRejected(
        testCase: ContractEquivalencePlan.Case, perturbation: any ContractArtifactPerturbation
    ) throws {
        let corpus = Self.corpus
        let language = testCase.language
        let snippet = try corpus.snippet(feature: testCase.feature, language: language)
        let original = corpus.artifact(
            source: snippet.source, fileName: snippet.fileName, language: language)
        let varied = testCase.variation.varied(
            ContractSnippet(
                feature: testCase.feature, language: language,
                source: snippet.source, fileName: snippet.fileName))
        let tolerance = testCase.variation.tolerance
        guard perturbation.isCaught(under: tolerance) else { return }
        let expected = try ContractArtifactProjection(
            union: [original] + varied.appended, tolerance: tolerance)
        let variedArtifact = corpus.artifact(
            source: varied.source, fileName: varied.fileName, language: language)
        guard !variedArtifact.types.isEmpty
            || !variedArtifact.freestandingFunctions.isEmpty
            || !variedArtifact.globalVariables.isEmpty else {
            Issue.record("\(testCase) declares nothing, so no perturbation of it can be caught")
            return
        }
        let broken = try ContractArtifactProjection(
            artifact: perturbation.perturbed(variedArtifact), tolerance: tolerance.variedSide)
        #expect(
            broken != expected,
            "\(testCase) still matches the original with \(perturbation.name)")
    }

    /// A variation whose rewrite left the source and the file name alone would pass the suite without
    /// parsing anything new.
    @Test("every variation really rewrites the snippet", arguments: plan.cases)
    func everyVariationChangesSomething(testCase: ContractEquivalencePlan.Case) throws {
        let snippet = try Self.corpus.snippet(feature: testCase.feature, language: testCase.language)
        let input = ContractSnippet(
            feature: testCase.feature, language: testCase.language,
            source: snippet.source, fileName: snippet.fileName)
        let varied = testCase.variation.varied(input)
        #expect(
            varied.source != input.source || varied.fileName != input.fileName,
            "\(testCase) is a no-op, so the case proves nothing")
    }
}
