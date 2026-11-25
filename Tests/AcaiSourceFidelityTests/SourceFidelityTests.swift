import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// Checks each parsed artifact against the source text it came from, rather than against a recorded
/// file. A golden pins whatever the parser produced, so a wrong value stays wrong once recorded;
/// these checks read the source instead, and so can disagree with a golden that agrees with itself.
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
        let known = KnownParserIssues().entries(for: subject)
        let covered = violations.filter { violation in known.contains { $0.matches(violation) } }
        #expect(
            violations.count == covered.count,
            Self.report(violations.filter { violation in !covered.contains { $0 == violation } }, of: subject)
        )

        guard !known.isEmpty else { return }
        withKnownIssue(Comment(rawValue: known.map(\.issue).joined(separator: "\n"))) {
            #expect(covered.isEmpty, Self.report(covered, of: subject))
        }
    }

    /// Parsing and checking every subject in turn, which is the cost this suite adds to a test run.
    @Test("checking the whole corpus stays inside its budget")
    func staysInsideItsBudget() throws {
        let subjects = Self.subjects
        let elapsed = try ContinuousClock().measure {
            for subject in subjects {
                _ = try Self.violations(of: subject)
            }
        }
        #expect(
            elapsed < .seconds(10),
            "checking \(subjects.count) subjects took \(elapsed), over this suite's 10-second budget"
        )
    }

    static func violations(of subject: SourceFidelityCorpus.Subject) throws -> [FidelityViolation] {
        SourceFidelityCheck(
            text: SourceText(try corpus.source(of: subject)),
            artifact: try corpus.artifact(of: subject),
            difference: SourceFidelityDifferences().difference(for: subject.parser.language)
        ).violations
    }

    static func report(_ violations: [FidelityViolation], of subject: SourceFidelityCorpus.Subject) -> Comment {
        Comment(rawValue: ([subject.label] + violations.map(\.description)).joined(separator: "\n"))
    }
}
