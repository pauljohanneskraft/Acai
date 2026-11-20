import Foundation
import Testing
@testable import AcaiCore

private let outerLanguage = CodeArtifact.SourceLanguage(rawValue: "collection-outer")
private let innerLanguage = CodeArtifact.SourceLanguage(rawValue: "collection-inner")

/// Claims the root for one language and a directory below it for another.
private struct NestedSpecsDetector: BuildSystemDetector {
    let innerPath: String

    func isPresent(at root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest").path)
    }

    func discoverSourceSpecs(at root: URL, requestedLanguages: [CodeArtifact.SourceLanguage]) -> [SourceSpec] {
        [
            SourceSpec(language: outerLanguage, sourceDirs: [root], root: root),
            SourceSpec(
                language: innerLanguage, sourceDirs: [root.appendingPathComponent(innerPath)], root: root
            )
        ]
    }
}

private struct NoFallback: BuildSystemDetector {
    func isPresent(at root: URL) -> Bool { false }

    func discoverSourceSpecs(at root: URL, requestedLanguages: [CodeArtifact.SourceLanguage]) -> [SourceSpec] {
        []
    }
}

private struct OneTypePerFileParser: CodeParser {
    let language: CodeArtifact.SourceLanguage
    let fileExtensions: [String]
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let name = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: [fileName]),
            types: [TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public)]
        )
    }
}

@Suite("Source collection over nested source directories", .timeLimit(.minutes(1)))
struct SourceCollectionEquivalenceTests {

    private func analyze(_ root: URL, innerPath: String) async throws -> Set<String> {
        let service = AnalysisService(
            parsers: [
                OneTypePerFileParser(language: outerLanguage, fileExtensions: ["outer"]),
                OneTypePerFileParser(language: innerLanguage, fileExtensions: ["inner"])
            ],
            projectDiscovery: ProjectDiscovery(
                detectors: [NestedSpecsDetector(innerPath: innerPath)], fallback: NoFallback()
            )
        )
        let artifact = try await service.analyzeProject(at: root, allowedLanguages: [], respectingGitignore: false)
        return Set(artifact.types.map(\.name))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-nested-collection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "".write(to: root.appendingPathComponent("manifest"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("Top.outer"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("a source directory inside a hidden directory below another spec's directory is still collected")
    func collectsHiddenNestedSourceDirectory() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inner = root.appendingPathComponent(".generated/src", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "".write(to: inner.appendingPathComponent("Hidden.inner"), atomically: true, encoding: .utf8)

        #expect(try await analyze(root, innerPath: ".generated/src") == ["Top", "Hidden"])
    }

    @Test("a source directory a sibling symbolic link aliases keeps its files under its own path")
    func collectsSourceDirectoryAliasedByEarlierLink() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inner = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "".write(to: inner.appendingPathComponent("Real.inner"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Alias"), withDestinationURL: inner
        )

        #expect(try await analyze(root, innerPath: "Sources") == ["Top", "Real"])
    }

    @Test("collection lists nothing more once the analysis is cancelled")
    func collectionObservesCancellation() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("a/b", isDirectory: true), withIntermediateDirectories: true
        )
        let listings = OperationCounter()
        let reads = DirectoryReadCache(listingCounter: listings)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return SourceFileIndex(
                sourceDirs: [root], extensions: ["outer"], excludingDirectories: [], reads: reads
            ).files(withExtensions: ["outer"], under: [root])
        }

        #expect(await task.value.isEmpty)
        #expect(listings.count == .zero)
    }
}
