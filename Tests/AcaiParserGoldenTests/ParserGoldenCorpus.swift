import Foundation
import AcaiCore
import AcaiLibrary

/// The fixture/golden pair store, located by `#filePath` rather than `Bundle.module` so it works
/// identically on macOS and Linux — the approach `AcaiExamplesTests` uses for the `Examples/`
/// goldens.
struct ParserGoldenCorpus {

    struct Fixture: Sendable, CustomStringConvertible {
        let parser: any CodeParser
        /// Also the `fileName` handed to the parser, so every `SourceLocation.filePath` in the
        /// golden is this relative name and not an absolute path that differs per machine.
        let fileName: String

        var description: String { fileName }
    }

    let directory: URL

    init(testFile: StaticString = #filePath) {
        directory = URL(fileURLWithPath: "\(testFile)").deletingLastPathComponent()
    }

    /// The artifact a stage pins. `.enriched` runs the pipeline with the configuration the *registry*
    /// holds for the language the parser reported — not a hand-written one — so the golden records what
    /// the engine really produces for this language.
    func artifact(of fixture: Fixture, stage: Stage) throws -> CodeArtifact {
        let parsed = fixture.parser.parse(source: try source(of: fixture), fileName: fixture.fileName)
        switch stage {
        case .raw:
            return parsed
        case .enriched:
            guard let configuration = AnalysisService.standard.registry
                .configuration(for: parsed.metadata.sourceLanguage) else {
                throw CorpusError.unregisteredLanguage(parsed.metadata.sourceLanguage.rawValue)
            }
            return parsed.enriched(configuration: configuration)
        }
    }

    enum CorpusError: Error, CustomStringConvertible {
        case unregisteredLanguage(String)

        var description: String {
            switch self {
            case .unregisteredLanguage(let language):
                return "'\(language)' has no configuration in AnalysisService.standard's registry"
            }
        }
    }

    func source(of fixture: Fixture) throws -> String {
        try String(
            contentsOf: directory.appendingPathComponent("Fixtures").appendingPathComponent(fixture.fileName),
            encoding: .utf8
        )
    }

    /// Which of a fixture's two pinned snapshots: the parser's raw output, or the same artifact after
    /// the enrichment pipeline has run with the language's registered configuration.
    enum Stage: String, Sendable, CaseIterable {
        case raw = ""
        case enriched = ".enriched"
    }

    func goldenURL(of fixture: Fixture, stage: Stage = .raw) -> URL {
        directory
            .appendingPathComponent("__Goldens__")
            .appendingPathComponent("\(fixture.fileName)\(stage.rawValue).json")
    }

    func golden(of fixture: Fixture, stage: Stage = .raw) throws -> String {
        try String(contentsOf: goldenURL(of: fixture, stage: stage), encoding: .utf8)
    }

    func record(_ snapshot: String, for fixture: Fixture, stage: Stage = .raw) throws {
        try snapshot.write(to: goldenURL(of: fixture, stage: stage), atomically: true, encoding: .utf8)
    }

    /// `ACAI_RECORD_PARSER_GOLDENS=1` rewrites every golden instead of comparing. Recording is never
    /// a fix for an unexpected drift — read the diff first.
    var isRecording: Bool {
        ProcessInfo.processInfo.environment["ACAI_RECORD_PARSER_GOLDENS"] == "1"
    }
}

/// A `CodeArtifact` encoded so two runs on two machines produce byte-identical text.
struct CodeArtifactSnapshot {
    let artifact: CodeArtifact

    func json() throws -> String {
        let encoder = JSONEncoder()
        // `.sortedKeys`: a `Dictionary`'s own order is not stable across runs.
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(artifact)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SnapshotError.notUTF8
        }
        return text + "\n"
    }

    enum SnapshotError: Error {
        case notUTF8
    }
}
