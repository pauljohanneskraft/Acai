import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// A base directory that mixes languages (here Swift + Python) is discovered and enriched per
/// language, but merges into a single `CodeArtifact` with one top-level language. These tests prove
/// the per-type `LanguageConfigurationResolver` classifies each type under *its own* language rather
/// than the single dominant one — the fix for the polyglot config-flattening bug.
@Suite("Polyglot per-type config resolution")
struct PolyglotConfigResolutionTests {

    /// Writes a Swift subdir and a Python subdir under one root, then analyses the whole root.
    private func analyzePolyglotFixture() throws -> CodeArtifact {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiPolyglot-\(UUID().uuidString)", isDirectory: true)
        let swiftDir = root.appendingPathComponent("swiftapp", isDirectory: true)
        let pyDir = root.appendingPathComponent("pyservice", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pyDir, withIntermediateDirectories: true)
        try """
        class SwiftModel {
            let items: [String] = []
        }
        """.write(to: swiftDir.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        try """
        class PyService:
            def __init__(self):
                self.values = []
        """.write(to: pyDir.appendingPathComponent("service.py"), atomically: true, encoding: .utf8)
        return try AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])
    }

    @Test func stampsEachTypeWithItsOwnLanguage() throws {
        let artifact = try analyzePolyglotFixture()
        let swiftType = try #require(artifact.types.first { $0.name == "SwiftModel" })
        let pyType = try #require(artifact.types.first { $0.name == "PyService" })
        #expect(swiftType.sourceLanguage == .swift)
        #expect(pyType.sourceLanguage == .python)
    }

    @Test func resolverReturnsEachLanguagesOwnConfiguration() throws {
        let artifact = try analyzePolyglotFixture()
        let resolver = artifact.standardLanguageResolver
        let swiftType = try #require(artifact.types.first { $0.name == "SwiftModel" })
        let pyType = try #require(artifact.types.first { $0.name == "PyService" })

        let swiftCollections = resolver.configuration(for: swiftType).collectionTypeNames
        let pyCollections = resolver.configuration(for: pyType).collectionTypeNames

        // The crux: two types in one artifact resolve to *different* language quirks. A single flat
        // config could only match one of them.
        #expect(swiftCollections != pyCollections)
        #expect(swiftCollections.contains("Array"))   // Swift's collection vocabulary
        #expect(pyCollections.contains("list"))       // Python's collection vocabulary
    }

    @Test func perTypeReEnrichmentIsIdempotentOnAPolyglotArtifact() throws {
        // The artifact is already enriched per-language by `AnalysisService`. Re-enriching it through
        // the per-type resolver must be a no-op — proving structural-edge inference classifies each
        // language's types with its own config. (Re-enriching with a single dominant config would
        // re-infer the non-dominant language's edges and change the relationship set.)
        let artifact = try analyzePolyglotFixture()
        let reEnriched = artifact.enriched(using: artifact.standardLanguageResolver)
        let key: (Relationship) -> String = { "\($0.source)→\($0.target):\($0.kind.rawValue)" }
        #expect(Set(reEnriched.relationships.map(key)) == Set(artifact.relationships.map(key)))
    }
}
