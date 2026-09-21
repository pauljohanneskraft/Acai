import Foundation
import Testing
import AcaiCore

// A source file that can't be read (invalid encoding, permissions) must not vanish silently and
// must not abort the rest of the analysis — it becomes a `ParseDiagnostic` on the artifact, which
// `HealthCheck` then counts.

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

    @Test("an unreadable file produces one diagnostic and does not abort the rest of the analysis")
    func unreadableFileYieldsDiagnostic() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("acai-unreadable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "Good".write(to: root.appendingPathComponent("good.stub"), atomically: true, encoding: .utf8)
        // Invalid UTF-8 byte sequence: a lone continuation byte can never start a valid scalar.
        let invalidUTF8 = Data([0xFF, 0xFE, 0x80, 0x80])
        FileManager.default.createFile(atPath: root.appendingPathComponent("bad.stub").path, contents: invalidUTF8)

        let service = AnalysisService(parsers: [StubParser()])
        let artifact = try service.analyzeProject(at: root, allowedLanguages: [])

        #expect(artifact.types.map(\.name) == ["Good"])

        let diagnostics = artifact.metadata.parseDiagnostics
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.kind == .unreadable)
        #expect(diagnostics.first?.location.filePath == "bad.stub")

        let report = HealthCheck(artifact: artifact).report
        #expect(report.diagnosticCount == 1)
        #expect(report.countsByKind["unreadable"] == 1)
    }
}
