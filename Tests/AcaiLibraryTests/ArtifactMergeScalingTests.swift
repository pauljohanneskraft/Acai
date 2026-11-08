import Foundation
import Testing
import AcaiArtifactGenerator
import AcaiLibrary

/// `CodeArtifact(merging:)` replaced a fold of pairwise `merging(with:)`, which copied both arrays
/// once per fragment and made assembling an analysis quadratic in the number of files (#485). These
/// pin the merged result unchanged and the copying linear, counted rather than timed so the
/// assertion means the same thing on loaded CI hardware.
@Suite("Artifact merge scaling")
struct ArtifactMergeScalingTests {

    private func fragments(count: Int) -> [CodeArtifact] {
        (0..<count).map { ArtifactGenerator(seed: UInt64($0) + 1).makeArtifact() }
    }

    private func fold(_ parts: [CodeArtifact]) -> CodeArtifact {
        parts.dropFirst().reduce(parts[0]) { $0.merging(with: $1) }
    }

    // MARK: - Result

    @Test func mergingMatchesThePairwiseFold() {
        let parts = fragments(count: 6)
        #expect(CodeArtifact(merging: parts) == fold(parts))
    }

    @Test func noFragmentsIsNilAndOneIsAdoptedUnchanged() {
        #expect(CodeArtifact(merging: []) == nil)
        let only = fragments(count: 1)[0]
        #expect(CodeArtifact(merging: [only]) == only)
    }

    @Test func toolVersionTakesTheFirstNonNil() {
        var parts = fragments(count: 3)
        parts[0].metadata.toolVersion = nil
        parts[1].metadata.toolVersion = "second"
        #expect(CodeArtifact(merging: parts)?.metadata.toolVersion == "second")
        #expect(CodeArtifact(merging: parts) == fold(parts))
    }

    // MARK: - Copying

    @Test func adoptingASingleFragmentCopiesNothing() {
        let counter = MergeElementCounter()
        _ = CodeArtifact(merging: fragments(count: 1), countingInto: counter)
        #expect(counter.elementsCopied == 0)
    }

    @Test func eachElementIsCopiedOnce() {
        let parts = fragments(count: 32)
        let total = parts.reduce(0) { $0 + $1.elementCount }
        let counter = MergeElementCounter()
        let merged = CodeArtifact(merging: parts, countingInto: counter)

        #expect(total > 0)
        #expect(counter.elementsCopied == total)
        #expect(counter.elementsCopied <= 2 * total)
        #expect(merged?.types.count == parts.reduce(0) { $0 + $1.types.count })
    }

    // MARK: - End to end

    private func elementsCopiedAnalysing(files: Int, in directory: URL) async throws -> Int {
        let counter = MergeElementCounter()
        let service = AnalysisService(
            parsers: AnalysisService.standard.parsers,
            projectDiscovery: AnalysisService.standard.projectDiscovery,
            mergeElementCounter: counter
        )
        try SourceCorpusGenerator(shape: .init(files: files, typesPerFile: 8), seed: 99).write(into: directory)
        let artifact = try await service.analyzeProject(at: directory, allowedLanguages: [])
        #expect(artifact.types.count >= files * 8)
        return counter.elementsCopied
    }

    @Test func doublingTheCorpusDoesNotMoreThanDoubleTheCopying() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiMergeScaling-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let small = try await elementsCopiedAnalysing(
            files: 40, in: root.appendingPathComponent("small", isDirectory: true)
        )
        let large = try await elementsCopiedAnalysing(
            files: 80, in: root.appendingPathComponent("large", isDirectory: true)
        )

        #expect(small > 0)
        #expect(Double(large) < 2.2 * Double(small))
    }

    // MARK: - Generator

    private var richShape: SourceCorpusGenerator.Shape {
        SourceCorpusGenerator.Shape(
            files: 3, typesPerFile: 2, extensionsPerFile: 1, sameNamedNestedTypesPerFile: 1, expressionDepth: 4
        )
    }

    @Test func theCorpusIsDeterministicPerSeed() {
        let first = SourceCorpusGenerator(shape: richShape, seed: 7).sources()
        #expect(SourceCorpusGenerator(shape: richShape, seed: 7).sources().map(\.text) == first.map(\.text))
        #expect(SourceCorpusGenerator(shape: richShape, seed: 8).sources().map(\.text) != first.map(\.text))
    }

    @Test(arguments: SourceCorpusGenerator.Language.allCases)
    func everyEmittedLanguageParsesCleanly(language: SourceCorpusGenerator.Language) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCorpus-\(language.rawValue)-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try SourceCorpusGenerator(shape: richShape, language: language, seed: 11).write(into: root)
        let artifact = try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])

        #expect(artifact.types.count >= 6)
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
    }
}
