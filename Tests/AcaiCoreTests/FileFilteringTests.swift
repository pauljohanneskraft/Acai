import Foundation
import Testing
import AcaiCore

/// `AnalysisService.analyzeProject`'s `includingFile` hook (B62): a caller-supplied predicate over
/// each candidate file's path, checked *before* the file is read — a caller-owned allow/blocklist
/// (e.g. `AcaiApp`'s per-codebase `FileFilter`) plugs in here so an excluded file is never parsed,
/// not merely hidden from the result afterward.
private struct SingleFileParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "fixture") }
    var fileExtensions: [String] { ["fx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let name = (fileName as NSString).lastPathComponent.replacingOccurrences(of: ".fx", with: "")
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

@Suite("AnalysisService file filtering")
struct FileFilteringTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCoreFileFilterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A file excluded by includingFile is never parsed")
    func excludedFileIsNeverParsed() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "".write(to: root.appendingPathComponent("Keep.fx"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("Skip.fx"), atomically: true, encoding: .utf8)

        let service = AnalysisService(parsers: [SingleFileParser()])
        let artifact = try service.analyzeProject(at: root, allowedLanguages: []) { relativePath in
            relativePath != "Skip.fx"
        }

        #expect(artifact.types.contains { $0.name == "Keep" })
        #expect(!artifact.types.contains { $0.name == "Skip" })
    }

    @Test("Omitting includingFile parses every file, unchanged from before it existed")
    func omittingFilterParsesEverything() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "".write(to: root.appendingPathComponent("A.fx"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("B.fx"), atomically: true, encoding: .utf8)

        let service = AnalysisService(parsers: [SingleFileParser()])
        let artifact = try service.analyzeProject(at: root, allowedLanguages: [])

        #expect(artifact.types.contains { $0.name == "A" })
        #expect(artifact.types.contains { $0.name == "B" })
    }
}
