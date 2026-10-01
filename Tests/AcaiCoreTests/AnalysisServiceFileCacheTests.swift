import Foundation
import Testing
@testable import AcaiCore

/// A `CodeParser` that counts every `parse` call and derives its one declared type's name from the
/// file's own content — so a test can tell a cached fragment from a freshly reparsed one just by
/// reading the artifact, not only by the call count.
private final class CountingParser: CodeParser, @unchecked Sendable {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "fixture") }
    var fileExtensions: [String] { ["fx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    private let lock = NSLock()
    private var count = 0

    var parsedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func parse(source: String, fileName: String) -> CodeArtifact {
        lock.lock()
        count += 1
        lock.unlock()
        let base = (fileName as NSString).lastPathComponent.replacingOccurrences(of: ".fx", with: "")
        let name = "\(base)_\(source)"
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

@Suite("AnalysisService per-file parse cache", .timeLimit(.minutes(1)))
struct AnalysisServiceFileCacheTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCoreFileCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["A", "B", "C"] {
            try "content-\(name)".write(
                to: root.appendingPathComponent("\(name).fx"), atomically: true, encoding: .utf8)
        }
        return root
    }

    /// Advances `url`'s modification date well past "now" so a subsequent analysis sees a changed
    /// fingerprint even on a filesystem with coarse mtime resolution.
    private func touch(_ url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
    }

    @Test func unchangedFilesAreNotReparsedAfterOneFileChanges() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parser = CountingParser()
        let service = AnalysisService(parsers: [parser])

        let first = try await service.analyzeProject(at: root, allowedLanguages: [], reusing: ParsedFileCache())
        #expect(parser.parsedCount == 3)

        try touch(root.appendingPathComponent("B.fx"), content: "content-B-edited")

        let second = try await service.analyzeProject(at: root, allowedLanguages: [], reusing: first.fileCache)
        #expect(parser.parsedCount == 4, "exactly one file changed, so exactly one more parse call is expected")

        // The edited file's content actually reached the result — not a stale cached fragment.
        #expect(second.artifact.types.contains { $0.name == "B_content-B-edited" })
        #expect(!second.artifact.types.contains { $0.name == "B_content-B" })
        // The untouched files' fragments were carried forward unchanged.
        #expect(second.artifact.types.contains { $0.name == "A_content-A" })
        #expect(second.artifact.types.contains { $0.name == "C_content-C" })
    }

    @Test func cachedAnalysisIsByteIdenticalToAColdOne() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let warmParser = CountingParser()
        let warmService = AnalysisService(parsers: [warmParser])
        let warm = try await warmService.analyzeProject(at: root, allowedLanguages: [], reusing: ParsedFileCache())
        try touch(root.appendingPathComponent("A.fx"), content: "content-A-edited")
        let warmed = try await warmService.analyzeProject(at: root, allowedLanguages: [], reusing: warm.fileCache)

        let coldParser = CountingParser()
        let coldService = AnalysisService(parsers: [coldParser])
        let cold = try await coldService.analyzeProject(at: root, allowedLanguages: [])

        #expect(warmed.artifact == cold)
    }

    @Test func aFileRemovedSinceTheCacheWasBuiltIsDroppedFromTheUpdatedCache() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parser = CountingParser()
        let service = AnalysisService(parsers: [parser])

        let first = try await service.analyzeProject(at: root, allowedLanguages: [], reusing: ParsedFileCache())
        try FileManager.default.removeItem(at: root.appendingPathComponent("C.fx"))

        let second = try await service.analyzeProject(at: root, allowedLanguages: [], reusing: first.fileCache)
        #expect(parser.parsedCount == 3, "the two surviving files are both unchanged, so neither reparses")
        #expect(!second.artifact.types.contains { $0.name == "C_content-C" })
    }

    @Test func aCacheFromADifferentToolVersionIsIgnoredEntirely() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parser = CountingParser()
        let service = AnalysisService(parsers: [parser])

        let foreignCache = ParsedFileCache(
            toolVersion: "not-\(AcaiConstants.standard.toolVersion)", entriesByRelativePath: [:])
        _ = try await service.analyzeProject(at: root, allowedLanguages: [], reusing: foreignCache)
        #expect(parser.parsedCount == 3, "a version mismatch must discard the whole cache, not just skip misses")
    }
}
