import Foundation
import AcaiCore

/// The checked-in *enriched* parser goldens, decoded back into `CodeArtifact`s.
///
/// The goldens under `Tests/AcaiParserGoldenTests/__Goldens__` pin two snapshots per fixture: the raw
/// parser output (`<file>.json`) and the same artifact after enrichment (`<file>.enriched.json`). This
/// corpus reads the enriched one, so a consumer gets the shape the diagram and metric layers actually
/// see without linking a parser or re-running extraction.
///
/// Located by `#filePath` rather than a resource bundle, like `AcaiExamplesTests` and
/// `ParserGoldenCorpus` — identical behaviour on macOS and Linux.
public struct ContractCorpus: Sendable {

    /// One pinned artifact: the fixture file the parser was handed, and the language it reports.
    public struct Entry: Sendable, Hashable {
        public let fileName: String
        public let language: CodeArtifact.SourceLanguage

        public init(fileName: String, language: CodeArtifact.SourceLanguage) {
            self.fileName = fileName
            self.language = language
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case missingGolden(fileName: String, url: URL)
        case languageMismatch(fileName: String, expected: String, found: String)

        public var description: String {
            switch self {
            case .missingGolden(let fileName, let url):
                return "no enriched golden for '\(fileName)' at \(url.path) — record it with "
                    + "ACAI_RECORD_PARSER_GOLDENS=1 swift test --filter AcaiParserGoldenTests"
            case .languageMismatch(let fileName, let expected, let found):
                return "'\(fileName)' pins language '\(found)', not the requested '\(expected)'"
            }
        }
    }

    public let directory: URL

    /// Points at the golden directory relative to this source file, walking out of
    /// `Sources/AcaiContractFixtures` to the repository root.
    public init(sourceFile: StaticString = #filePath) {
        directory = URL(fileURLWithPath: "\(sourceFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests")
            .appendingPathComponent("AcaiParserGoldenTests")
            .appendingPathComponent("__Goldens__")
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for fileName: String) -> URL {
        directory.appendingPathComponent("\(fileName).enriched.json")
    }

    /// The enriched artifact pinned for `fileName`. `language` is the language the caller expects the
    /// fixture to pin; a mismatch throws rather than silently handing back another language's shape
    /// (a fixture's parser may report a language its extension doesn't imply — a C++ header, say).
    public func artifact(
        for fileName: String, language: CodeArtifact.SourceLanguage
    ) throws -> CodeArtifact {
        let url = url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure.missingGolden(fileName: fileName, url: url)
        }
        let artifact = try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: url))
        guard artifact.metadata.sourceLanguage == language else {
            throw Failure.languageMismatch(
                fileName: fileName, expected: language.rawValue,
                found: artifact.metadata.sourceLanguage.rawValue)
        }
        return artifact
    }

    public func artifact(for entry: Entry) throws -> CodeArtifact {
        try artifact(for: entry.fileName, language: entry.language)
    }
}
