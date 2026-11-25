import Foundation
import AcaiCore
import AcaiLibrary

/// Every parser input the fidelity checks run on: the golden fixtures and the contract matrix's
/// per-language snippets, both located by `#filePath` and left where they are, so neither corpus
/// has to be copied to be held to the source.
struct SourceFidelityCorpus {

    /// One source file and the parser the engine routes its extension to.
    struct Subject: Sendable, CustomStringConvertible {
        let label: String
        let url: URL
        let parser: any CodeParser

        /// The `fileName` handed to the parser, so every `SourceLocation.filePath` is this relative
        /// name rather than an absolute path that differs per machine.
        var fileName: String { url.lastPathComponent }

        var description: String { label }
    }

    let parsers: [any CodeParser]
    private let goldenFixtures: URL
    private let contractFeatures: URL

    init(
        testFile: StaticString = #filePath,
        parsers: [any CodeParser] = AnalysisService.standardParsers
    ) {
        let tests = URL(fileURLWithPath: "\(testFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        goldenFixtures = tests.appendingPathComponent("AcaiParserGoldenTests/Fixtures")
        contractFeatures = tests.appendingPathComponent("AcaiContractTests/Features")
        self.parsers = parsers
    }

    /// The parser whose `fileExtensions` claim this extension, in `standardParsers` order — the same
    /// routing the engine applies, so a `.jsx` subject is parsed as JavaScript and a `.tsx` one as
    /// TypeScript without this suite restating either mapping.
    func parser(forPathExtension pathExtension: String) -> (any CodeParser)? {
        let lowered = pathExtension.lowercased()
        return parsers.first { parser in
            parser.fileExtensions.contains { $0.lowercased() == lowered }
        }
    }

    var subjects: [Subject] {
        (goldenSubjects + contractSubjects).sorted { $0.label < $1.label }
    }

    var goldenSubjects: [Subject] {
        files(in: goldenFixtures).compactMap { subject(at: $0, labelledBy: "golden") }
    }

    var contractSubjects: [Subject] {
        directories(in: contractFeatures).flatMap { feature in
            files(in: feature).compactMap { subject(at: $0, labelledBy: "contract/\(feature.lastPathComponent)") }
        }
    }

    func source(of subject: Subject) throws -> String {
        try String(contentsOf: subject.url, encoding: .utf8)
    }

    func artifact(of subject: Subject) throws -> CodeArtifact {
        subject.parser.parse(source: try source(of: subject), fileName: subject.fileName)
    }

    /// A waiver or an expectation has no parser, which is how both are skipped.
    private func subject(at url: URL, labelledBy prefix: String) -> Subject? {
        guard let parser = parser(forPathExtension: url.pathExtension) else { return nil }
        return Subject(label: "\(prefix)/\(url.lastPathComponent)", url: url, parser: parser)
    }

    private func files(in directory: URL) -> [URL] {
        contents(of: directory).filter { $0.isDirectoryResource == false }
    }

    private func directories(in directory: URL) -> [URL] {
        contents(of: directory).filter { $0.isDirectoryResource == true }
    }

    private func contents(of directory: URL) -> [URL] {
        let found = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        )
        return (found ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

extension URL {
    fileprivate var isDirectoryResource: Bool? {
        try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    }
}
