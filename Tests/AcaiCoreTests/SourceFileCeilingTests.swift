import Foundation
import Testing
import AcaiCore

/// Each file was read whole into a `String` with no bound, so a generated file that escaped every
/// exclusion — a bundled `.js`, a vendored single-file library — was parsed in full. A file over the
/// ceiling is now skipped and *said* to be skipped, so a type the user expected to find and cannot
/// is explained rather than simply absent.
private struct CeilingFixtureParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "ceilingFixture") }
    var fileExtensions: [String] { ["cx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let name = (fileName as NSString).lastPathComponent.replacingOccurrences(of: ".cx", with: "")
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

@Suite("Per-file size ceiling", .timeLimit(.minutes(1)))
struct SourceFileCeilingTests {

    private let manager = FileManager.default

    private func makeRoot() throws -> URL {
        let url = manager.temporaryDirectory
            .appendingPathComponent("AcaiCeilingTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a file over the ceiling is skipped, and its size is reported")
    func oversizedFileIsSkipped() async throws {
        let root = try makeRoot()
        defer { try? manager.removeItem(at: root) }
        try "small".write(to: root.appendingPathComponent("Small.cx"), atomically: true, encoding: .utf8)
        try String(repeating: "x", count: 512)
            .write(to: root.appendingPathComponent("Huge.cx"), atomically: true, encoding: .utf8)

        let service = AnalysisService(parsers: [CeilingFixtureParser()], maximumSourceFileBytes: 64)
        let artifact = try await service.analyzeProject(at: root, allowedLanguages: [])

        #expect(artifact.types.map(\.name) == ["Small"])
        let skipped = artifact.metadata.parseDiagnostics.filter { $0.kind == .skipped }
        #expect(skipped.map(\.location.filePath) == ["Huge.cx"])
        #expect(skipped.first?.message.contains("512 bytes") == true)
        #expect(skipped.first?.message.contains("64-byte") == true)
    }

    @Test("the skip reaches the health report as its own kind")
    func skipIsCounted() async throws {
        let root = try makeRoot()
        defer { try? manager.removeItem(at: root) }
        try "ok".write(to: root.appendingPathComponent("Kept.cx"), atomically: true, encoding: .utf8)
        try String(repeating: "y", count: 512)
            .write(to: root.appendingPathComponent("Dropped.cx"), atomically: true, encoding: .utf8)

        let service = AnalysisService(parsers: [CeilingFixtureParser()], maximumSourceFileBytes: 64)
        let report = HealthCheck(artifact: try await service.analyzeProject(at: root, allowedLanguages: []))
            .report
        #expect(report.countsByKind["skipped"] == 1)
    }

    @Test("a file at the ceiling is parsed; only one over it is not")
    func ceilingIsInclusive() async throws {
        let root = try makeRoot()
        defer { try? manager.removeItem(at: root) }
        try String(repeating: "z", count: 64)
            .write(to: root.appendingPathComponent("Exact.cx"), atomically: true, encoding: .utf8)

        let service = AnalysisService(parsers: [CeilingFixtureParser()], maximumSourceFileBytes: 64)
        let artifact = try await service.analyzeProject(at: root, allowedLanguages: [])
        #expect(artifact.types.map(\.name) == ["Exact"])
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
    }

    @Test("the default ceiling leaves ordinary source untouched")
    func defaultCeilingIsGenerous() {
        #expect(AcaiConstants.standard.maximumSourceFileBytes >= 1024 * 1024)
    }

    @Test("a symlinked file over the ceiling is skipped, not read through the link's own tiny size")
    func symlinkedOversizedFileIsSkipped() async throws {
        let manager = self.manager
        let root = try makeRoot()
        defer { try? manager.removeItem(at: root) }
        let target = root.appendingPathComponent("RealHuge.cx")
        try String(repeating: "x", count: 512).write(to: target, atomically: true, encoding: .utf8)
        let linkRoot = root.appendingPathComponent("linked", isDirectory: true)
        try manager.createDirectory(at: linkRoot, withIntermediateDirectories: true)
        try manager.createSymbolicLink(
            at: linkRoot.appendingPathComponent("Huge.cx"), withDestinationURL: target)

        let service = AnalysisService(parsers: [CeilingFixtureParser()], maximumSourceFileBytes: 64)
        let artifact = try await service.analyzeProject(at: linkRoot, allowedLanguages: [])

        #expect(artifact.types.isEmpty)
        let skipped = artifact.metadata.parseDiagnostics.filter { $0.kind == .skipped }
        #expect(skipped.map(\.location.filePath) == ["Huge.cx"])
        #expect(skipped.first?.message.contains("512 bytes") == true)
    }
}
