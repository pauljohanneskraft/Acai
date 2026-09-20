import Foundation
import AcaiCore
import AcaiLibrary

/// The fixture/golden pair store, located relative to this file rather than through
/// `Bundle.module` so it works identically under `swift test` on macOS and Linux — the same
/// approach `AcaiExamplesTests` uses for the `Examples/` goldens.
struct ParserGoldenCorpus {

    /// One fixture: the source to parse and the parser to parse it with.
    struct Fixture: Sendable, CustomStringConvertible {
        let parser: any CodeParser
        /// The fixture's file name (`classes.py`). Also the `fileName` handed to the parser, so
        /// every `SourceLocation.filePath` in the golden is this stable relative name and never an
        /// absolute path that would differ per machine.
        let fileName: String

        var description: String { fileName }
    }

    let directory: URL

    init(testFile: StaticString = #filePath) {
        directory = URL(fileURLWithPath: "\(testFile)").deletingLastPathComponent()
    }

    func source(of fixture: Fixture) throws -> String {
        try String(
            contentsOf: directory.appendingPathComponent("Fixtures").appendingPathComponent(fixture.fileName),
            encoding: .utf8
        )
    }

    func goldenURL(of fixture: Fixture) -> URL {
        directory
            .appendingPathComponent("__Goldens__")
            .appendingPathComponent("\(fixture.fileName).json")
    }

    func golden(of fixture: Fixture) throws -> String {
        try String(contentsOf: goldenURL(of: fixture), encoding: .utf8)
    }

    func record(_ snapshot: String, for fixture: Fixture) throws {
        try snapshot.write(to: goldenURL(of: fixture), atomically: true, encoding: .utf8)
    }

    /// Set `ACAI_RECORD_PARSER_GOLDENS=1` to rewrite every golden from the current parsers instead
    /// of comparing against them. Recording is never a fix for an unexpected drift — read the diff
    /// first; these goldens exist precisely to make a restructuring prove itself.
    var isRecording: Bool {
        ProcessInfo.processInfo.environment["ACAI_RECORD_PARSER_GOLDENS"] == "1"
    }
}

/// A `CodeArtifact` encoded so two runs on two machines produce byte-identical text: keys sorted
/// (a `Dictionary`'s own order is not stable across runs) and slashes left unescaped so the file
/// stays readable as a diff.
struct CodeArtifactSnapshot {
    let artifact: CodeArtifact

    func json() throws -> String {
        let encoder = JSONEncoder()
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
