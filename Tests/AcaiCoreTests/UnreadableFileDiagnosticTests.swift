import Foundation
import Testing
@testable import AcaiCore

// A source file that can't be read as the engine expects must not vanish silently and must not abort
// the rest of the analysis. One that is merely in the wrong encoding is decoded with its invalid
// bytes replaced, so its types survive; one that can't be read at all becomes a `ParseDiagnostic`.

extension CodeArtifact.SourceLanguage {
    fileprivate static let stub = CodeArtifact.SourceLanguage(rawValue: "unreadableFileStub")
}

private struct StubParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .stub }
    var fileExtensions: [String] { ["stub"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let name = String(source.prefix(while: { !$0.isWhitespace }))
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public
        )
        return CodeArtifact(metadata: .init(sourceLanguage: .stub, filePaths: [fileName]), types: [type])
    }
}

@Suite("Unreadable-file diagnostics")
struct UnreadableFileDiagnosticTests {

    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("acai-unreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    @Test("a file in a non-UTF-8 encoding keeps its types and reports the bytes that were replaced")
    func nonUTF8FileIsDecodedLossily() async throws {
        try await withTempDir { root in
            try "Good".write(to: root.appendingPathComponent("good.stub"), atomically: true, encoding: .utf8)
            // Latin-1, as older C, C++ and Java sources commonly are: 0xFC and 0xDF are each a
            // lone byte no valid UTF-8 scalar can start with.
            let latin1 = try #require("Widget // Grüße".data(using: .isoLatin1))
            try latin1.write(to: root.appendingPathComponent("latin1.stub"))

            let service = AnalysisService(parsers: [StubParser()])
            let artifact = try await service.analyzeProject(at: root, allowedLanguages: [])

            #expect(artifact.types.map(\.name).sorted() == ["Good", "Widget"])

            let diagnostics = artifact.metadata.parseDiagnostics
            #expect(diagnostics.map(\.kind) == [.lossyDecoding])
            #expect(diagnostics.first?.location.filePath == "latin1.stub")
            #expect(diagnostics.first?.message.contains("latin1.stub") == true)
        }
    }

    @Test("lossy decoding is reported in health but does not lower the score")
    func lossyDecodingIsReportedButNotScored() async throws {
        try await withTempDir { root in
            let latin1 = try #require("Widget // Grüße".data(using: .isoLatin1))
            try latin1.write(to: root.appendingPathComponent("latin1.stub"))

            let service = AnalysisService(parsers: [StubParser()])
            let artifact = try await service.analyzeProject(at: root, allowedLanguages: [])

            let report = HealthCheck(artifact: artifact).report
            #expect(report.diagnosticCount == 1)
            #expect(report.countsByKind["lossyDecoding"] == 1)
            #expect(report.score == 1)
        }
    }

    @Test("a file that cannot be read at all produces one unreadable diagnostic")
    func unreadableFileYieldsDiagnostic() async throws {
        try await withTempDir { root in
            let parser = SourceFileBatchParser(
                codeParser: StubParser(), rootURL: root, concurrencyLimit: 1,
                maximumFileBytes: AcaiConstants.standard.maximumSourceFileBytes)
            let outcome = try await parser.parse([root.appendingPathComponent("gone.stub")], reusing: nil)

            #expect(outcome.files.isEmpty)
            #expect(outcome.diagnostics.map(\.kind) == [.unreadable])
            #expect(outcome.diagnostics.first?.location.filePath == "gone.stub")
        }
    }
}
