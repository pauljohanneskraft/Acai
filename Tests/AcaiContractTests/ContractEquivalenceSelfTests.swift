import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// A way a parser could mishandle a variation, applied to the artifact the variation really produced.
protocol ContractArtifactPerturbation: Sendable, CustomStringConvertible {
    var name: String { get }
    /// `false` where the tolerance deliberately excuses this difference, so the check is not expected
    /// to catch it.
    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool
    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact
}

extension ContractArtifactPerturbation {
    var description: String { name }
    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool { true }
}

/// What a variation that routed the file to no grammar at all looks like (#609).
struct ContractDroppedDeclarations: ContractArtifactPerturbation {
    let name = "every declaration dropped"

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        var perturbed = artifact
        perturbed.types = []
        perturbed.freestandingFunctions = []
        perturbed.globalVariables = []
        perturbed.relationships = []
        return perturbed
    }
}

/// What a line ending left in the source looks like once it reaches a name.
struct ContractRenamedFirstDeclaration: ContractArtifactPerturbation {
    let name = "a stray character left on the first name"

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        var perturbed = artifact
        if !perturbed.types.isEmpty {
            perturbed.types[0].name += "\u{0D}"
        } else if !perturbed.freestandingFunctions.isEmpty {
            perturbed.freestandingFunctions[0].name += "\u{0D}"
        } else if !perturbed.globalVariables.isEmpty {
            perturbed.globalVariables[0].name += "\u{0D}"
        }
        return perturbed
    }
}

/// What a location counted from the wrong line looks like.
struct ContractShiftedLines: ContractArtifactPerturbation {
    let name = "every location one line further down"

    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool { !tolerance.ignoresLocations }

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        ContractLocationShift(lines: 1, columns: 0).applied(to: artifact)
    }
}

/// What a column measured in UTF-8 bytes rather than characters looks like (#607).
struct ContractShiftedColumns: ContractArtifactPerturbation {
    let name = "every location one column further right"

    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool { !tolerance.ignoresLocations }

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        ContractLocationShift(lines: 0, columns: 1).applied(to: artifact)
    }
}

/// Moves every location in an artifact, so a perturbation does not have to know where they all are.
struct ContractLocationShift {
    let lines: Int
    let columns: Int

    func applied(to artifact: CodeArtifact) -> CodeArtifact {
        var shifted = artifact
        shifted.types = artifact.types.map { applied(to: $0) }
        shifted.freestandingFunctions = artifact.freestandingFunctions.map { applied(to: $0) }
        shifted.globalVariables = artifact.globalVariables.map { applied(to: $0) }
        return shifted
    }

    private func applied(to type: TypeDeclaration) -> TypeDeclaration {
        var shifted = type
        shifted.location = applied(to: type.location)
        shifted.members = type.members.map { applied(to: $0) }
        shifted.nestedTypes = type.nestedTypes.map { applied(to: $0) }
        shifted.enumCases = type.enumCases.map { enumCase in
            var shiftedCase = enumCase
            shiftedCase.location = applied(to: enumCase.location)
            return shiftedCase
        }
        return shifted
    }

    private func applied(to member: Member) -> Member {
        var shifted = member
        shifted.location = applied(to: member.location)
        shifted.callSites = member.callSites.map { callSite in
            var shiftedSite = callSite
            shiftedSite.location = applied(to: callSite.location)
            return shiftedSite
        }
        return shifted
    }

    private func applied(to location: SourceLocation?) -> SourceLocation? {
        guard var location else { return nil }
        location.line += lines
        location.column += columns
        location.endLine = location.endLine.map { $0 + lines }
        return location
    }
}

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

    /// One case per variation kind, on a snippet rich enough for every perturbation to bite.
    static let cases: [ContractEquivalencePlan.Case] = {
        let plan = ContractEquivalencePlan(corpus: corpus)
        var seen: Set<String> = []
        return plan.cases.filter { testCase in
            let kind = testCase.variation.name.components(separatedBy: " ").first ?? ""
            guard testCase.language.stem == "swift", seen.insert(kind).inserted else { return false }
            return true
        }
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
        let expected = try ContractArtifactProjection(
            union: [original] + varied.appended, tolerance: tolerance)
        let variedArtifact = corpus.artifact(
            source: varied.source, fileName: varied.fileName, language: language)
        let broken = try ContractArtifactProjection(
            artifact: perturbation.perturbed(variedArtifact), tolerance: tolerance)
        guard perturbation.isCaught(under: tolerance) else {
            return
        }
        #expect(
            broken != expected,
            "\(testCase) still matches the original with \(perturbation.name)")
    }

    /// A variation whose rewrite left the source and the file name alone would pass the suite without
    /// parsing anything new.
    @Test("every variation really rewrites the snippet", arguments: ContractEquivalencePlan(corpus: corpus).cases)
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
