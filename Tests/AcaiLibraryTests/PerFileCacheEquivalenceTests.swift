import Foundation
import Testing
import AcaiLibrary

private final class CountingParser: CodeParser, @unchecked Sendable {
    let wrapped: any CodeParser
    private let lock = NSLock()
    private var count = 0

    init(_ wrapped: any CodeParser) {
        self.wrapped = wrapped
    }

    var language: CodeArtifact.SourceLanguage { wrapped.language }
    var fileExtensions: [String] { wrapped.fileExtensions }
    var configuration: LanguageConfiguration { wrapped.configuration }

    var parsedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func parse(source: String, fileName: String) -> CodeArtifact {
        lock.lock()
        count += 1
        lock.unlock()
        return wrapped.parse(source: source, fileName: fileName)
    }
}

/// Every built-in parser's output survives the per-file cache's disk round trip unchanged.
@Suite("Per-file cache equivalence")
struct PerFileCacheEquivalenceTests {

    private func copyPolyglotCorpus(testFile: StaticString = #filePath) throws -> URL {
        let corpus = URL(fileURLWithPath: "\(testFile)")
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AcaiParserGoldenTests/Fixtures")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiPerFileCacheEquivalence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: corpus, to: root)
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-3600)],
                ofItemAtPath: root.appendingPathComponent(name).path)
        }
        return root
    }

    private func countingService() -> (AnalysisService, [CountingParser]) {
        let parsers = AnalysisService.standard.parsers.map(CountingParser.init)
        let service = AnalysisService(parsers: parsers, projectDiscovery: AnalysisService.standard.projectDiscovery)
        return (service, parsers)
    }

    private func canonicalJSON(_ artifact: CodeArtifact) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(artifact)
    }

    @Test func aFullyCachedAnalysisMatchesAColdOne() async throws {
        let root = try copyPolyglotCorpus()
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiPerFileCacheEquivalenceStore-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        let cache = AnalysisCache(store: AnalysisStore(directory: storeDirectory), for: root)

        let (coldService, coldParsers) = countingService()
        let cold = try await coldService.analyzeProject(at: root, allowedLanguages: [], reusing: cache)
        #expect(coldParsers.map(\.parsedCount).reduce(0, +) > 0)

        let (warmService, warmParsers) = countingService()
        let warm = try await warmService.analyzeProject(at: root, allowedLanguages: [], reusing: cache)

        #expect(warmParsers.map(\.parsedCount).reduce(0, +) == 0, "every file is answered from disk")
        #expect(warm == cold)
        #expect(try canonicalJSON(warm) == canonicalJSON(cold))
    }
}
