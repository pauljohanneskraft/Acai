import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("StatisticDetailBuilder")
struct StatisticDetailBuilderTests {

    private func type(_ name: String, module: String) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    /// `Hub` depends on both `Beta` and `Alpha`, giving `Hub` fan-out 2 and `Alpha`/`Beta` a tied
    /// fan-in of 1 each — enough to exercise filtering zeros, descending order and the name tie-break.
    private func sampleArtifact() -> CodeArtifact {
        let hub = type("Hub", module: "Core")
        let beta = type("Beta", module: "Core")
        let alpha = type("Alpha", module: "Core")
        let rels = [
            Relationship(kind: .dependency, source: "Hub", target: "Beta"),
            Relationship(kind: .dependency, source: "Hub", target: "Alpha")
        ]
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [hub, beta, alpha], relationships: rels)
        return artifact.enriched(using: artifact.standardLanguageResolver)
    }

    @Test func typeDetailDropsZerosAndBreaksTiesByName() {
        let artifact = sampleArtifact()
        let metrics = artifact.computeMetrics()
        let builder = StatisticDetailBuilder(artifact: artifact)

        let byFanIn = builder.typeDetail("Fan-in", "Callers", metrics.types, by: \.fanIn)
        #expect(byFanIn.rows.map(\.id) == ["Alpha", "Beta"])
    }

    @Test func typeDetailResolvesTheDeclaringFile() {
        let artifact = sampleArtifact()
        let metrics = artifact.computeMetrics()
        let builder = StatisticDetailBuilder(artifact: artifact)

        let byFanOut = builder.typeDetail("Fan-out", "Callees", metrics.types, by: \.fanOut)
        #expect(byFanOut.rows.map(\.id) == ["Hub"])
        #expect(byFanOut.rows.first?.relativePath == "Sources/Core/Hub.swift")
    }

    @Test func typeDetailShortensANestedName() {
        let inner = TypeDeclaration(
            id: "Outer.Inner", name: "Inner", qualifiedName: "Outer.Inner", kind: .class,
            accessLevel: .public,
            location: SourceLocation(filePath: "Sources/Core/Outer.swift", line: 2, column: 5))
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .class, accessLevel: .public,
            nestedTypes: [inner],
            location: SourceLocation(filePath: "Sources/Core/Outer.swift", line: 1, column: 1))
        let caller = type("Caller", module: "Core")
        let rels = [Relationship(kind: .dependency, source: "Caller", target: "Outer.Inner")]
        let unenrichedArtifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [outer, caller], relationships: rels)
        let artifact = unenrichedArtifact.enriched(using: unenrichedArtifact.standardLanguageResolver)
        let metrics = artifact.computeMetrics()
        let builder = StatisticDetailBuilder(artifact: artifact)

        let byFanIn = builder.typeDetail("Fan-in", "Callers", metrics.types, by: \.fanIn)
        #expect(byFanIn.rows.first?.name == "Inner")
    }

    @Test func moduleDetailResolvesADirectoryFromARepresentativeType() {
        let unenrichedArtifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [type("A", module: "Core")], relationships: [])
        let artifact = unenrichedArtifact.enriched(using: unenrichedArtifact.standardLanguageResolver)
        let metrics = artifact.computeMetrics()
        let builder = StatisticDetailBuilder(artifact: artifact)

        let detail = builder.moduleDetail(
            "Types", "Count", metrics.modules, value: { Double($0.typeCount) }, format: { "\(Int($0))" })
        #expect(detail.rows.first?.id == "Core")
        #expect(detail.rows.first?.relativePath == "Sources/Core")
    }

    @Test func relativePathIsNilWithoutAnArtifact() {
        let metrics = sampleArtifact().computeMetrics()
        let builder = StatisticDetailBuilder(artifact: nil)

        let byFanOut = builder.typeDetail("Fan-out", "Callees", metrics.types, by: \.fanOut)
        #expect(byFanOut.rows.first?.relativePath == nil)
    }
}
