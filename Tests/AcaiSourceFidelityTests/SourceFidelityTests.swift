import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// Checks each parsed artifact against the source text it came from, rather than against a recorded
/// file. A golden pins whatever the parser produced, so a wrong value stays wrong once recorded;
/// these checks read the source instead and can therefore disagree with a golden that agrees with
/// itself.
@Suite("Artifacts agree with their source", .timeLimit(.minutes(1)))
struct SourceFidelityTests {

    static let corpus = SourceFidelityCorpus()
    static let subjects = corpus.subjects

    @Test("every fixture and snippet is checked")
    func corpusCoversBothSets() {
        #expect(Self.corpus.goldenSubjects.count >= 17, "the golden fixtures are not being found")
        #expect(Self.corpus.contractSubjects.count >= 200, "the contract snippets are not being found")
        #expect(
            Set(Self.subjects.map(\.parser.language)).count == AnalysisService.standardParsers.count,
            "a registered language contributes no subject"
        )
    }

    @Test("a parsed artifact agrees with its source", arguments: subjects)
    func agreesWithSource(subject: SourceFidelityCorpus.Subject) throws {
        let violations = try Self.violations(of: subject)
        #expect(violations.isEmpty, "\(subject.label)\n\(violations.map(\.description).joined(separator: "\n"))")
    }

    static func violations(of subject: SourceFidelityCorpus.Subject) throws -> [FidelityViolation] {
        SourceFidelityCheck(
            text: SourceText(try corpus.source(of: subject)),
            artifact: try corpus.artifact(of: subject),
            difference: SourceFidelityDifferences().difference(for: subject.parser.language)
        ).violations
    }
}
