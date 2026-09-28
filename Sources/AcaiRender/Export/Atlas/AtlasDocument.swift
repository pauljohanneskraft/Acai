import AcaiCore
import CoreGraphics
import Foundation

/// Splits `itemCount` items into fixed-size pages — at least one page even when `itemCount == 0`,
/// so an empty section still gets a page saying so rather than vanishing.
public struct PagedSection {
    public let itemCount: Int
    public let itemsPerPage: Int

    public init(itemCount: Int, itemsPerPage: Int) {
        precondition(itemsPerPage > 0, "itemsPerPage must be positive")
        self.itemCount = itemCount
        self.itemsPerPage = itemsPerPage
    }

    public var pageCount: Int {
        itemCount == 0 ? 1 : (itemCount + itemsPerPage - 1) / itemsPerPage
    }

    public func range(forPage pageIndex: Int) -> Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let start = pageIndex * itemsPerPage
        return start..<min(start + itemsPerPage, itemCount)
    }
}

/// One diagram's page: its heading plus the image the caller rendered for it. Rendering happens
/// outside — the app renders through the on-canvas view models that hold the user's saved node
/// positions, `acai atlas` and `acai_atlas` through this module's headless exporters — so the
/// bundling below stays the one implementation either way.
public struct AtlasDiagramPage: Sendable {
    public enum Image: Sendable {
        case rendered(Data)
        /// This diagram kind has no PNG-export path (the chart-style kinds — module coupling,
        /// hotspots — are not canvas diagrams with a layout model).
        case unsupported
        /// Rendering was attempted and failed; the page says so rather than silently disappearing,
        /// so the Atlas's page count never depends on whether rendering happened to succeed.
        case failed
    }

    public let name: String
    /// The diagram kind's English display name, e.g. "Class Diagram".
    public let kind: String
    public let image: Image

    public init(name: String, kind: String, image: Image) {
        self.name = name
        self.kind = kind
        self.image = image
    }
}

enum AtlasPage {
    case title
    case diagram(AtlasDiagramPage)
    case stats(lines: [String], pageIndex: Int, totalPages: Int)
    case findings(items: [AtlasFinding], pageIndex: Int, totalPages: Int)
}

/// The Codebase Atlas: one codebase's diagrams, statistics and findings bundled into a single
/// multi-page PDF. Every input is already resolved by the caller, so this is a pure layout and
/// pagination pass that produces the same document from the app, the CLI and the MCP server.
public struct AtlasDocument: Sendable {
    public let codebaseName: String
    public let diagrams: [AtlasDiagramPage]
    public let metrics: CodeMetrics
    public let findings: [AtlasFinding]
    /// Stamped on the title page. Injected rather than read from the clock so a caller can produce
    /// a byte-stable document.
    public let generatedAt: Date

    public static let pageSize = CGSize(width: 612, height: 792)
    public static let margin: CGFloat = 48
    /// The scale diagram images are rendered at before being fitted to a page.
    public static let renderScale: CGFloat = 2
    public static let findingsPerPage = 14
    /// Bumped whenever the Atlas's page layout/content changes shape.
    public static let formatVersion = 1

    public init(
        codebaseName: String,
        diagrams: [AtlasDiagramPage],
        metrics: CodeMetrics,
        findings: [AtlasFinding],
        generatedAt: Date = Date()
    ) {
        self.codebaseName = codebaseName
        self.diagrams = diagrams
        self.metrics = metrics
        self.findings = findings
        self.generatedAt = generatedAt
    }

    private var contentBounds: CGRect {
        CGRect(x: Self.margin, y: Self.margin,
               width: Self.pageSize.width - Self.margin * 2, height: Self.pageSize.height - Self.margin * 2)
    }

    public func pdfData() throws -> Data {
        let pages = assemblePages()
        let writer = PDFDocumentWriter(
            pageSize: Self.pageSize,
            metadata: PDFDocumentMetadata(
                title: "\(codebaseName) — Codebase Atlas",
                creator: "Acai",
                subject: "Acai Codebase Atlas — Format \(Self.formatVersion)"))
        return try writer.write(pageCount: pages.count) { index, context in
            draw(pages[index], in: context)
        }
    }

    private func assemblePages() -> [AtlasPage] {
        var pages: [AtlasPage] = [.title]
        pages.append(contentsOf: diagrams.map(AtlasPage.diagram))

        let statLines = AtlasStatistics(metrics: metrics).lines
        let statsPaging = PagedSection(itemCount: statLines.count, itemsPerPage: AtlasStatistics.linesPerPage)
        for pageIndex in 0..<statsPaging.pageCount {
            pages.append(.stats(
                lines: Array(statLines[statsPaging.range(forPage: pageIndex)]),
                pageIndex: pageIndex, totalPages: statsPaging.pageCount))
        }

        let findingsPaging = PagedSection(itemCount: findings.count, itemsPerPage: Self.findingsPerPage)
        for pageIndex in 0..<findingsPaging.pageCount {
            pages.append(.findings(
                items: Array(findings[findingsPaging.range(forPage: pageIndex)]),
                pageIndex: pageIndex, totalPages: findingsPaging.pageCount))
        }
        return pages
    }

    private func draw(_ page: AtlasPage, in context: CGContext) {
        switch page {
        case .title:
            drawTitlePage(in: context)
        case .diagram(let diagram):
            drawDiagramPage(diagram, in: context)
        case .stats(let lines, let pageIndex, let totalPages):
            drawStatsPage(lines: lines, pageIndex: pageIndex, totalPages: totalPages, in: context)
        case .findings(let items, let pageIndex, let totalPages):
            drawFindingsPage(items: items, pageIndex: pageIndex, totalPages: totalPages, in: context)
        }
    }

    private func drawTitlePage(in context: CGContext) {
        var canvas = AtlasPageCanvas(context: context, bounds: contentBounds)
        canvas.drawLine(codebaseName, fontSize: 28, bold: true, spacing: AtlasPageCanvas.lineSpacing)
        canvas.drawLine("Codebase Atlas", fontSize: 16, spacing: AtlasPageCanvas.titleSpacing)
        canvas.drawLine(
            "Generated \(Self.generatedAtFormatter.string(from: generatedAt))", fontSize: 12,
            spacing: AtlasPageCanvas.lineSpacing)
        canvas.drawLine("Diagrams: \(diagrams.count)", fontSize: 12, spacing: AtlasPageCanvas.tightSpacing)
        canvas.drawLine("Findings: \(findings.count)", fontSize: 12, spacing: AtlasPageCanvas.tightSpacing)
        canvas.drawLine(
            "Acai Codebase Atlas — Format \(Self.formatVersion)", fontSize: 10,
            spacing: AtlasPageCanvas.tightSpacing)
    }

    private func drawDiagramPage(_ diagram: AtlasDiagramPage, in context: CGContext) {
        var canvas = AtlasPageCanvas(context: context, bounds: contentBounds)
        canvas.drawLine(diagram.name, fontSize: 16, bold: true, spacing: AtlasPageCanvas.lineSpacing)
        canvas.drawLine(diagram.kind, fontSize: 11, spacing: AtlasPageCanvas.headingSpacing)
        switch diagram.image {
        case .rendered(let data):
            if let image = data.cgImage {
                canvas.drawImage(image)
            } else {
                canvas.drawLine("This diagram's rendered image could not be decoded.", fontSize: 12)
            }
        case .unsupported:
            canvas.drawLine("This diagram type isn't included in image exports yet.", fontSize: 12)
        case .failed:
            canvas.drawLine("This diagram could not be rendered in this environment.", fontSize: 12)
        }
    }

    private func drawStatsPage(lines: [String], pageIndex: Int, totalPages: Int, in context: CGContext) {
        var canvas = AtlasPageCanvas(context: context, bounds: contentBounds)
        let title = totalPages > 1 ? "Statistics (\(pageIndex + 1)/\(totalPages))" : "Statistics"
        canvas.drawLine(title, fontSize: 18, bold: true, spacing: AtlasPageCanvas.sectionSpacing)
        for line in lines {
            canvas.drawLine(line, fontSize: 11, spacing: AtlasPageCanvas.entrySpacing)
        }
    }

    private func drawFindingsPage(
        items: [AtlasFinding], pageIndex: Int, totalPages: Int, in context: CGContext
    ) {
        var canvas = AtlasPageCanvas(context: context, bounds: contentBounds)
        let title = totalPages > 1 ? "Findings (\(pageIndex + 1)/\(totalPages))" : "Findings"
        canvas.drawLine(title, fontSize: 18, bold: true, spacing: AtlasPageCanvas.sectionSpacing)
        guard !items.isEmpty else {
            canvas.drawLine("No findings for this codebase.", fontSize: 12)
            return
        }
        for finding in items {
            canvas.drawLine(finding.line, fontSize: 11, spacing: AtlasPageCanvas.entrySpacing)
        }
    }

    /// Pinned, not the reader's locale: this date is written into the exported atlas, which stays
    /// the same document whatever language the app is running in.
    private static let generatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
