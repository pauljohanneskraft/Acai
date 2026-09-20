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
