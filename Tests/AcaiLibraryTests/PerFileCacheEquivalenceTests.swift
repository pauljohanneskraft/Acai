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

    private func write(_ files: [String: String], in root: URL) throws {
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: url.path)
        }
    }

    /// Two projects sharing a `Core` module, a type name in two modules, file-private namesakes and a
    /// Python name two files of one package declare.
    private let scopedTree = [
        "app-ios/Package.swift": "// swift-tools-version:5.9",
        "app-ios/Sources/Core/Foo.swift": "public class Foo {}\nprivate struct Helper {}",
        "app-ios/Sources/Core/Bar.swift": "public class Bar { let foo: Foo }\nprivate struct Helper {}",
        "app-ios/Sources/UI/Foo.swift": "public class Foo { let bar: Bar }",
        "app-mac/Package.swift": "// swift-tools-version:5.9",
        "app-mac/Sources/Core/Foo.swift": "public class Foo {}",
        "py/pyproject.toml": "[project]\nname = \"py\"",
        "py/pkg/a.py": "class Model:\n    pass\n",
        "py/pkg/b.py": "class Model:\n    pass\n"
    ]

    @Test func aWarmAnalysisScopesIdsExactlyAsAColdOne() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiPerFileCacheScoping-\(UUID().uuidString)", isDirectory: true)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiPerFileCacheScopingStore-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        try write(scopedTree, in: root)
        let cache = AnalysisCache(store: AnalysisStore(directory: storeDirectory), for: root)

        let cold = try await countingService().0.analyzeProject(at: root, allowedLanguages: [], reusing: cache)
        let ids = Set(cold.flattened().map(\.id))
        #expect(ids.isSuperset(of: ["app-ios/Core.Foo", "app-ios/UI.Foo", "app-mac/Core.Foo"]))
        #expect(ids.isSuperset(of: [
            "app-ios/Sources/Core/Foo.swift:Helper", "app-ios/Sources/Core/Bar.swift:Helper",
            "py/pkg/a.py:Model", "py/pkg/b.py:Model"
        ]))

        let (warmService, warmParsers) = countingService()
        let warm = try await warmService.analyzeProject(at: root, allowedLanguages: [], reusing: cache)
        #expect(warmParsers.map(\.parsedCount).reduce(0, +) == 0)
        #expect(try canonicalJSON(warm) == canonicalJSON(cold))

        try write(["app-mac/Sources/Core/Copy.swift": "public class Foo {}"], in: root)
        let (partialService, partialParsers) = countingService()
        let partial = try await partialService.analyzeProject(at: root, allowedLanguages: [], reusing: cache)
        let uncached = try await countingService().0.analyzeProject(at: root, allowedLanguages: [])
        #expect(partialParsers.map(\.parsedCount).reduce(0, +) == 1, "only the new file is parsed")
        #expect(partial.flattened().contains { $0.id == "app-mac/Sources/Core/Foo.swift:Foo" })
        #expect(try canonicalJSON(partial) == canonicalJSON(uncached))
    }
}
