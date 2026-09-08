import Testing
import AcaiCore
@testable import AcaiApp

@Suite("CodeMetrics.TypeMetric.shortName")
struct TypeMetricShortNameTests {

    private func typeMetric(for declarations: [TypeDeclaration], id: String) throws -> CodeMetrics.TypeMetric {
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift), types: declarations, relationships: [])
        let enriched = artifact.enriched(using: artifact.standardLanguageResolver)
        return try #require(enriched.computeMetrics().types.first { $0.id == id })
    }

    @Test func returnsTheLastDotSeparatedComponentOfANestedName() throws {
        let inner = TypeDeclaration(
            id: "Outer.Inner", name: "Inner", qualifiedName: "Outer.Inner", kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "Sources/Core/Outer.swift", line: 2, column: 5))
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .class, accessLevel: .public,
            nestedTypes: [inner], location: SourceLocation(filePath: "Sources/Core/Outer.swift", line: 1, column: 1))
        let metric = try typeMetric(for: [outer], id: "Outer.Inner")
        #expect(metric.shortName == "Inner")
    }

    @Test func returnsTheWholeNameWhenThereIsNoDot() throws {
        let type = TypeDeclaration(
            id: "Baz", name: "Baz", qualifiedName: "Baz", kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "Sources/Core/Baz.swift", line: 1, column: 1))
        let metric = try typeMetric(for: [type], id: "Baz")
        #expect(metric.shortName == "Baz")
    }
}
