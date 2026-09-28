import Foundation
import PDFKit
import Testing
@testable import AcaiCore
@testable import AcaiRender

@Suite("Atlas Document")
struct AtlasDocumentTests {

    private let codebaseName = "Atlas Fixture"

    private func emptyMetrics() -> CodeMetrics {
        CodeMetrics(
            counts: .init(
                totalTypes: 1, byKind: [:], protocols: 0, globalVariables: 0, freestandingFunctions: 0,
                methods: 0, properties: 0, relationships: 0, relationshipsByKind: [:]),
            modules: [], types: [])
    }

    private func findings(count: Int) -> [AtlasFinding] {
        (0..<count).map { index in
            AtlasFinding(
                kind: .violation, severity: .warning, title: "Issue \(index)",
                message: "Something worth flagging.",
                location: SourceLocation(filePath: "Widget.swift", line: index + 1, column: 1))
        }
    }

    private func diagramPages(_ count: Int) -> [AtlasDiagramPage] {
        (0..<count).map { index in
            AtlasDiagramPage(name: "Diagram \(index)", subtitle: "Class Diagram", image: .unsupported)
        }
    }

    private func statsPageCount(for metrics: CodeMetrics) -> Int {
        let lineCount = AtlasStatistics(metrics: metrics).lines.count
        return PagedSection(itemCount: lineCount, itemsPerPage: AtlasStatistics.linesPerPage).pageCount
    }

    private func findingsPageCount(for findings: [AtlasFinding]) -> Int {
        PagedSection(itemCount: findings.count, itemsPerPage: AtlasDocument.findingsPerPage).pageCount
    }

    private func document(diagrams: [AtlasDiagramPage], findings: [AtlasFinding]) -> AtlasDocument {
        AtlasDocument(
            codebaseName: codebaseName, diagrams: diagrams, metrics: emptyMetrics(), findings: findings)
    }

    /// Findings count (20) deliberately crosses `AtlasDocument.findingsPerPage` (14).
    @Test func pageCountMatchesDiagramsStatsAndFindings() throws {
        let diagrams = diagramPages(2)
        let findingsList = findings(count: 20)
        let data = try document(diagrams: diagrams, findings: findingsList).pdfData()

        let statsPages = statsPageCount(for: emptyMetrics())
        let findingsPages = findingsPageCount(for: findingsList)

        #expect(statsPages > 1, "fixture should exercise stats pagination too")
        #expect(findingsPages > 1, "fixture must cross the findings-per-page boundary")

        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1 + diagrams.count + statsPages + findingsPages)
    }

    @Test func zeroFindingsStillYieldsOnePage() throws {
        let diagrams = diagramPages(1)
        let data = try document(diagrams: diagrams, findings: []).pdfData()

        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1 + diagrams.count + statsPageCount(for: emptyMetrics()) + 1)
    }

    @Test func noDiagramsStillProducesTitleStatsAndFindingsPages() throws {
        let data = try document(diagrams: [], findings: []).pdfData()

        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1 + statsPageCount(for: emptyMetrics()) + 1)
    }

    @Test func titlePageCarriesTheNameAndTheFormatMarker() throws {
        let data = try document(diagrams: [], findings: []).pdfData()

        let pdf = try #require(PDFDocument(data: data))
        let titlePageText = try #require(pdf.page(at: 0)?.string)
        #expect(titlePageText.contains(codebaseName))
        #expect(titlePageText.contains("Codebase Atlas"))
        #expect(titlePageText.contains("Format \(AtlasDocument.formatVersion)"))
    }

    /// The generation date is injected, so the same inputs produce the same bytes twice.
    @Test func sameInputsProduceTheSameDocument() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let make = {
            AtlasDocument(
                codebaseName: codebaseName, diagrams: diagramPages(1), metrics: emptyMetrics(),
                findings: findings(count: 3), generatedAt: generatedAt)
        }
        let first = try #require(PDFDocument(data: try make().pdfData()))
        let second = try #require(PDFDocument(data: try make().pdfData()))
        #expect(first.page(at: 0)?.string == second.page(at: 0)?.string)
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
