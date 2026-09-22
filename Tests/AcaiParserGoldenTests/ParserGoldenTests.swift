import Foundation
import Testing
import AcaiCore
import AcaiLibrary

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

    @Test("parsed artifact matches its checked-in golden", arguments: fixtures)
    func matchesGolden(fixture: ParserGoldenCorpus.Fixture) throws {
        let corpus = ParserGoldenCorpus()
        let artifact = fixture.parser.parse(
            source: try corpus.source(of: fixture), fileName: fixture.fileName
        )
        let snapshot = try CodeArtifactSnapshot(artifact: artifact).json()

        guard !corpus.isRecording else {
            try corpus.record(snapshot, for: fixture)
            return
        }

        let golden = try corpus.golden(of: fixture)
        #expect(
            snapshot == golden,
            """
            \(fixture.fileName) parsed differently than its golden.
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
}
