import Foundation
import Testing
import AcaiCore
import AcaiLibrary
import AcaiContractFixtures

/// Characterization tests: each fixture's whole encoded `CodeArtifact` is pinned to a checked-in
/// golden, so a restructuring of the extraction layer has to reproduce output exactly rather than
/// only satisfy the assertions the per-language suites happen to make.
///
/// A drift here is not a reason to re-record. Read the diff: either it is a regression, or it is a
/// deliberate behaviour change that belongs in its own commit with the golden update beside it.
@Suite("Parser output goldens")
struct ParserGoldenTests {

    /// Python and Dart in depth (the two languages restructured against these goldens); one broad
    /// fixture for every other language, since they share the tier being replaced.
    static let fixtures: [ParserGoldenCorpus.Fixture] = [
        .init(parser: PythonCodeParser(), fileName: "classes.py"),
        .init(parser: PythonCodeParser(), fileName: "annotations.py"),
        .init(parser: PythonCodeParser(), fileName: "bodies.py"),
        .init(parser: PythonCodeParser(), fileName: "module.py"),
        .init(parser: KotlinCodeParser(), fileName: "shop.kt"),
        .init(parser: JavaCodeParser(), fileName: "Shop.java"),
        .init(parser: JSCodeParser(), fileName: "shop.ts"),
        .init(parser: JSCodeParser(isTypeScript: false), fileName: "shop.js"),
        .init(parser: DartCodeParser(), fileName: "shop.dart"),
        .init(parser: DartCodeParser(), fileName: "globals.dart"),
        .init(parser: DartCodeParser(), fileName: "members.dart"),
        .init(parser: DartCodeParser(), fileName: "types.dart"),
        .init(parser: CCodeParser(), fileName: "shop.c"),
        .init(parser: CppCodeParser(), fileName: "shop.cpp"),
        .init(parser: SwiftCodeParser(), fileName: "Shop.swift")
    ]

    @Test("parsed artifact matches its checked-in golden", arguments: fixtures, ParserGoldenCorpus.Stage.allCases)
    func matchesGolden(fixture: ParserGoldenCorpus.Fixture, stage: ParserGoldenCorpus.Stage) throws {
        let corpus = ParserGoldenCorpus()
        let artifact = try corpus.artifact(of: fixture, stage: stage)
        let snapshot = try CodeArtifactSnapshot(artifact: artifact).json()

        guard !corpus.isRecording else {
            try corpus.record(snapshot, for: fixture, stage: stage)
            return
        }

        let golden = try corpus.golden(of: fixture, stage: stage)
        #expect(
            snapshot == golden,
            """
            \(fixture.fileName) (\(stage)) parsed differently than its golden.
            Read the diff before re-recording — see this suite's documentation.
            """
        )
    }

    /// A golden of an empty artifact would pass the comparison above while proving nothing.
    @Test("every fixture actually produces declarations", arguments: fixtures)
    func fixtureIsNotVacuous(fixture: ParserGoldenCorpus.Fixture) throws {
        let corpus = ParserGoldenCorpus()
        let artifact = fixture.parser.parse(
            source: try corpus.source(of: fixture), fileName: fixture.fileName
        )
        #expect(!artifact.types.isEmpty, "\(fixture.fileName) produced no types")
        #expect(
            artifact.types.contains { !$0.members.isEmpty },
            "\(fixture.fileName) produced no members"
        )
    }

    /// The enriched goldens are also the corpus `AcaiContractFixtures` hands to consumers that don't
    /// link a parser, so every one has to decode back into the artifact it was recorded from.
    @Test("the enriched golden round-trips through ContractCorpus", arguments: fixtures)
    func enrichedGoldenRoundTrips(fixture: ParserGoldenCorpus.Fixture) throws {
        let corpus = ParserGoldenCorpus()
        let recorded = try corpus.artifact(of: fixture, stage: .enriched)
        let decoded = try ContractCorpus().artifact(
            for: fixture.fileName, language: recorded.metadata.sourceLanguage)
        #expect(decoded == recorded, "\(fixture.fileName) did not decode back to the recorded artifact")
    }
}
