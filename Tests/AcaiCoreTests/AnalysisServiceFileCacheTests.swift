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

    /// A source tree plus its own private analysis store, so one test's cache can never be another's.
    private struct Fixture {
        let root: URL
        let store: AnalysisStore
        let storeDirectory: URL

        var cache: AnalysisCache { AnalysisCache(store: store, for: root) }

        var storedFragments: ParsedFileCache? { cache.reusableFragments() }

        var storedCacheFiles: [URL] {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: storeDirectory, includingPropertiesForKeys: nil)) ?? []
            return contents.filter { $0.pathExtension == "filecache" }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: storeDirectory)
        }
    }

    private func makeFixture() throws -> Fixture {
        let unique = UUID().uuidString
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCoreFileCacheTests-\(unique)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["A", "B", "C"] {
            try "content-\(name)".write(
                to: root.appendingPathComponent("\(name).fx"), atomically: true, encoding: .utf8)
        }
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCoreFileCacheStore-\(unique)", isDirectory: true)
        return Fixture(root: root, store: AnalysisStore(directory: storeDirectory), storeDirectory: storeDirectory)
    }

    /// Advances `url`'s modification date well past "now" so a subsequent analysis sees a changed
    /// fingerprint even on a filesystem with coarse mtime resolution.
    private func touch(_ url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
    }

    @Test func unchangedFilesAreNotReparsedAfterOneFileChanges() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let parser = CountingParser()
        let service = AnalysisService(parsers: [parser])

        _ = try await service.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: fixture.cache)
        #expect(parser.parsedCount == 3)

        try touch(fixture.root.appendingPathComponent("B.fx"), content: "content-B-edited")

        let second = try await service.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: fixture.cache)
        #expect(parser.parsedCount == 4, "exactly one file changed, so exactly one more parse call is expected")

        // The edited file's content actually reached the result — not a stale cached fragment.
        #expect(second.types.contains { $0.name == "B_content-B-edited" })
        #expect(!second.types.contains { $0.name == "B_content-B" })
        // The untouched files' fragments were carried forward unchanged.
        #expect(second.types.contains { $0.name == "A_content-A" })
        #expect(second.types.contains { $0.name == "C_content-C" })
    }

    @Test func cachedAnalysisIsByteIdenticalToAColdOne() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let warmService = AnalysisService(parsers: [CountingParser()])
        _ = try await warmService.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: fixture.cache)
        try touch(fixture.root.appendingPathComponent("A.fx"), content: "content-A-edited")
        let warmed = try await warmService.analyzeProject(
            at: fixture.root, allowedLanguages: [], reusing: fixture.cache)

        let coldService = AnalysisService(parsers: [CountingParser()])
        let cold = try await coldService.analyzeProject(at: fixture.root, allowedLanguages: [])

        #expect(warmed == cold)
    }

    @Test func aFileRemovedSinceTheCacheWasBuiltIsDroppedFromTheUpdatedCache() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let parser = CountingParser()
        let service = AnalysisService(parsers: [parser])

        _ = try await service.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: fixture.cache)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("C.fx"))

        let second = try await service.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: fixture.cache)
        #expect(parser.parsedCount == 3, "the two surviving files are both unchanged, so neither reparses")
        #expect(!second.types.contains { $0.name == "C_content-C" })

        // The surviving files are still cached, so dropping the removed one didn't discard the rest.
        let surviving = try #require(SourceFileFingerprint(
            file: fixture.root.appendingPathComponent("A.fx"), relativeTo: fixture.root))
        #expect(fixture.storedFragments?.fragment(for: surviving) != nil)
    }

    @Test func aCacheFromADifferentToolVersionIsIgnoredEntirely() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let parser = CountingParser()
        let service = AnalysisService(parsers: [parser])

        // A fragment whose fingerprint matches the file on disk exactly, so only the tool-version
        // stamp can be what makes it unusable.
        let fingerprint = try #require(SourceFileFingerprint(
            file: fixture.root.appendingPathComponent("A.fx"), relativeTo: fixture.root))
        let foreign = ParsedFileCache(
            toolVersion: "not-\(AcaiConstants.standard.toolVersion)",
            entriesByRelativePath: [fingerprint.relativePath: fingerprint.entry(for: CodeArtifact(
                metadata: .init(sourceLanguage: .init(rawValue: "fixture"))))])
        try fixture.store.writeFileCache(foreign, forResolvedPath: fixture.root.resolvingSymlinksInPath().path)

        _ = try await service.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: fixture.cache)
        #expect(parser.parsedCount == 3, "a version mismatch must discard the whole cache, not just skip misses")
    }

    /// The guarantee the ephemeral-tree callers rely on: analyzing a directory nothing will revisit
    /// (a git revision extracted to a temporary folder) must not leave a cache file behind for it.
    @Test func aDisabledCacheNeitherReadsNorWritesAnything() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let parser = CountingParser()
        let service = AnalysisService(parsers: [parser])

        _ = try await service.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: .disabled)
        _ = try await service.analyzeProject(at: fixture.root, allowedLanguages: [], reusing: .disabled)

        #expect(parser.parsedCount == 6, "nothing is reused between two uncached analyses")
        #expect(fixture.storedCacheFiles.isEmpty)
        #expect(AnalysisCache.disabled.reusableFragments() == nil)
    }
}
