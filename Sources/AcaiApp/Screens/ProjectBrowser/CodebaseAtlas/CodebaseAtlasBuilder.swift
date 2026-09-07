import AcaiCore
import AcaiRender
import CoreGraphics
import Foundation

/// Splits `itemCount` items into fixed-size pages — at least one page even when `itemCount == 0`,
/// so an empty section still gets a page saying so rather than vanishing.
struct PagedSection {
    let itemCount: Int
    let itemsPerPage: Int

    init(itemCount: Int, itemsPerPage: Int) {
        precondition(itemsPerPage > 0, "itemsPerPage must be positive")
        self.itemCount = itemCount
        self.itemsPerPage = itemsPerPage
    }

    var pageCount: Int {
        itemCount == 0 ? 1 : (itemCount + itemsPerPage - 1) / itemsPerPage
    }

    func range(forPage pageIndex: Int) -> Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let start = pageIndex * itemsPerPage
        return start..<min(start + itemsPerPage, itemCount)
    }
}

enum AtlasPage {
    case title
    case diagram(GeneratedDiagram, AtlasDiagramRenderOutcome)
    case stats(lines: [String], pageIndex: Int, totalPages: Int)
    case findings(items: [Finding], pageIndex: Int, totalPages: Int)
}

/// `@MainActor` because diagram PNG rendering goes through `ImageRenderer`, which requires it —
/// this also makes the struct implicitly `Sendable` despite `Finding`/`Codebase` not being
/// `Sendable` themselves, so it can be captured by `ActivityCenter.run`'s `@Sendable` closure.
@MainActor
struct CodebaseAtlasBuilder {
    let codebase: Codebase
    let artifact: CodeArtifact
    let diagrams: [GeneratedDiagram]
    let metrics: CodeMetrics
    let findings: [Finding]

    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 48
    static let renderScale: CGFloat = 2
    static let findingsPerPage = 14
    /// Bumped whenever the Atlas's page layout/content changes shape.
    static let formatVersion = 1

    private var contentBounds: CGRect {
        CGRect(x: Self.margin, y: Self.margin,
               width: Self.pageSize.width - Self.margin * 2, height: Self.pageSize.height - Self.margin * 2)
    }

    func build() async throws -> Data {
        let pages = try await assemblePages()
        let writer = PDFDocumentWriter(
            pageSize: Self.pageSize,
            metadata: PDFDocumentMetadata(
                title: "\(codebase.name) — Codebase Atlas",
                creator: "Acai",
                subject: "Acai Codebase Atlas — Format \(Self.formatVersion)"))
        return try writer.write(pageCount: pages.count) { index, context in
            draw(pages[index], in: context)
        }
    }

    private func assemblePages() async throws -> [AtlasPage] {
        let diagramRenderer = CodebaseAtlasDiagramRenderer(codebase: codebase, artifact: artifact)
        var pages: [AtlasPage] = [.title]
        for diagram in diagrams {
            pages.append(.diagram(diagram, diagramRenderer.render(diagram, scale: Self.renderScale)))
            await Task.yield()
        }

        let statLines = CodebaseAtlasStatsFormatter(metrics: metrics).lines
        let statsPaging = PagedSection(
            itemCount: statLines.count, itemsPerPage: CodebaseAtlasStatsFormatter.linesPerPage)
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
        case .diagram(let diagram, let outcome):
            drawDiagramPage(diagram, outcome, in: context)
        case .stats(let lines, let pageIndex, let totalPages):
            drawStatsPage(lines: lines, pageIndex: pageIndex, totalPages: totalPages, in: context)
        case .findings(let items, let pageIndex, let totalPages):
            drawFindingsPage(items: items, pageIndex: pageIndex, totalPages: totalPages, in: context)
        }
    }

    private func drawTitlePage(in context: CGContext) {
        var canvas = AtlasPageCanvas(context: context, bounds: contentBounds)
        canvas.drawLine(codebase.name, fontSize: 28, bold: true, spacing: 4)
        canvas.drawLine("Codebase Atlas", fontSize: 16, spacing: 24)
        canvas.drawLine("Generated \(Self.generatedAtFormatter.string(from: Date()))", fontSize: 12, spacing: 4)
        canvas.drawLine("Diagrams: \(diagrams.count)", fontSize: 12, spacing: 2)
        canvas.drawLine("Findings: \(findings.count)", fontSize: 12, spacing: 2)
        canvas.drawLine("Acai Codebase Atlas — Format \(Self.formatVersion)", fontSize: 10, spacing: 2)
    }

    private func drawDiagramPage(
        _ diagram: GeneratedDiagram, _ outcome: AtlasDiagramRenderOutcome, in context: CGContext
    ) {
        var canvas = AtlasPageCanvas(context: context, bounds: contentBounds)
        canvas.drawLine(diagram.name, fontSize: 16, bold: true, spacing: 4)
        canvas.drawLine(diagram.type.displayName, fontSize: 11, spacing: 12)
        switch outcome {
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
        canvas.drawLine(title, fontSize: 18, bold: true, spacing: 16)
        for line in lines {
            canvas.drawLine(line, fontSize: 11, spacing: 8)
        }
    }

    private func drawFindingsPage(items: [Finding], pageIndex: Int, totalPages: Int, in context: CGContext) {
        var canvas = AtlasPageCanvas(context: context, bounds: contentBounds)
        let title = totalPages > 1 ? "Findings (\(pageIndex + 1)/\(totalPages))" : "Findings"
        canvas.drawLine(title, fontSize: 18, bold: true, spacing: 16)
        guard !items.isEmpty else {
            canvas.drawLine("No findings for this codebase.", fontSize: 12)
            return
        }
        for finding in items {
            canvas.drawLine(findingLine(finding), fontSize: 11, spacing: 8)
        }
    }

    private func findingLine(_ finding: Finding) -> String {
        var line = "[\(finding.severity.label)] \(finding.kind.displayName) — \(finding.title): \(finding.message)"
        if let location = finding.location {
            line += " (\(location.filePath):\(location.line))"
        }
        return line
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
