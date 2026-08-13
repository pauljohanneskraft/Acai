import Foundation
import PDFKit
import Testing
@testable import AcaiApp
@testable import AcaiCore

@Suite("Codebase Atlas Export")
@MainActor
struct CodebaseAtlasExportTests {

    private func codebase() -> Codebase {
        Codebase(id: UUID(), name: "Atlas Fixture", directoryPath: "/tmp/atlas-fixture")
    }

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Widget.swift"]),
            types: [TypeDeclaration(id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class,
                accessLevel: .public)]
        )
    }

    private func emptyMetrics() -> CodeMetrics {
        CodeMetrics(
            counts: .init(
                totalTypes: 1, byKind: [:], protocols: 0, globalVariables: 0, freestandingFunctions: 0,
                methods: 0, properties: 0, relationships: 0, relationshipsByKind: [:]),
            modules: [], types: [])
    }

    private func findings(count: Int, codebaseID: UUID, codebaseName: String) -> [Finding] {
        (0..<count).map { index in
            Finding(
                id: "finding-\(index)", kind: .violation, severity: .warning,
                codebaseID: codebaseID, codebaseName: codebaseName,
                title: "Issue \(index)", message: "Something worth flagging.",
                location: SourceLocation(filePath: "Widget.swift", line: index + 1, column: 1),
                reference: nil, indexedAt: nil)
        }
    }

    private func diagram(_ type: DiagramType, codebaseID: UUID) -> GeneratedDiagram {
        GeneratedDiagram(name: "\(type.rawValue) diagram", content: .init(type: type), codebaseID: codebaseID)
    }

    private func statsPageCount(for metrics: CodeMetrics) -> Int {
        let lineCount = CodebaseAtlasStatsFormatter(metrics: metrics).lines.count
        return PagedSection(itemCount: lineCount, itemsPerPage: CodebaseAtlasStatsFormatter.linesPerPage).pageCount
    }

    private func findingsPageCount(for findings: [Finding]) -> Int {
        PagedSection(itemCount: findings.count, itemsPerPage: CodebaseAtlasBuilder.findingsPerPage).pageCount
    }

    /// Findings count (20) deliberately crosses `CodebaseAtlasBuilder.findingsPerPage` (14).
    @Test func pageCountMatchesDiagramsStatsAndFindings() async throws {
        let codebase = codebase()
        let diagrams = [
            diagram(.classDiagram, codebaseID: codebase.id),
            diagram(.moduleCoupling, codebaseID: codebase.id)
        ]
        let metrics = emptyMetrics()
        let findingsList = findings(count: 20, codebaseID: codebase.id, codebaseName: codebase.name)

        let builder = CodebaseAtlasBuilder(
            codebase: codebase, artifact: artifact(), diagrams: diagrams, metrics: metrics, findings: findingsList)
        let data = try await builder.build()

        let statsPages = statsPageCount(for: metrics)
        let findingsPages = findingsPageCount(for: findingsList)
        let expectedPageCount = 1 + diagrams.count + statsPages + findingsPages

        #expect(statsPages > 1, "fixture should exercise stats pagination too")
        #expect(findingsPages > 1, "fixture must cross the findings-per-page boundary")

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == expectedPageCount)
    }

    @Test func zeroFindingsStillYieldsOnePage() async throws {
        let codebase = codebase()
        let diagrams = [diagram(.classDiagram, codebaseID: codebase.id)]
        let metrics = emptyMetrics()

        let builder = CodebaseAtlasBuilder(
            codebase: codebase, artifact: artifact(), diagrams: diagrams, metrics: metrics, findings: [])
        let data = try await builder.build()

        let expectedPageCount = 1 + diagrams.count + statsPageCount(for: metrics) + 1

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == expectedPageCount)
    }

    @Test func noDiagramsStillProducesTitleStatsAndFindingsPages() async throws {
        let codebase = codebase()
        let metrics = emptyMetrics()

        let builder = CodebaseAtlasBuilder(
            codebase: codebase, artifact: artifact(), diagrams: [], metrics: metrics, findings: [])
        let data = try await builder.build()

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1 + statsPageCount(for: metrics) + 1)
    }

    @Test func titlePageTextIsExtractable() async throws {
        let codebase = codebase()
        let metrics = emptyMetrics()
        let builder = CodebaseAtlasBuilder(
            codebase: codebase, artifact: artifact(), diagrams: [], metrics: metrics, findings: [])
        let data = try await builder.build()

        let document = try #require(PDFDocument(data: data))
        let titlePageText = try #require(document.page(at: 0)?.string)
        #expect(titlePageText.contains(codebase.name))
        #expect(titlePageText.contains("Codebase Atlas"))
        #expect(titlePageText.contains("Format \(CodebaseAtlasBuilder.formatVersion)"))
    }
}

@Suite("Paged Section")
struct PagedSectionTests {
    @Test func emptyStillYieldsOnePage() {
        #expect(PagedSection(itemCount: 0, itemsPerPage: 10).pageCount == 1)
        #expect(PagedSection(itemCount: 0, itemsPerPage: 10).range(forPage: 0) == 0..<0)
    }

    @Test func exactMultipleDoesNotOverflowAPage() {
        let paging = PagedSection(itemCount: 20, itemsPerPage: 10)
        #expect(paging.pageCount == 2)
        #expect(paging.range(forPage: 0) == 0..<10)
        #expect(paging.range(forPage: 1) == 10..<20)
    }

    @Test func remainderGetsItsOwnPage() {
        let paging = PagedSection(itemCount: 21, itemsPerPage: 10)
        #expect(paging.pageCount == 3)
        #expect(paging.range(forPage: 2) == 20..<21)
    }
}
