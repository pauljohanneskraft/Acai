import CoreGraphics
import Foundation

/// Document-level metadata for a written PDF (the "version marker" a format's own reader can key
/// off later, alongside whatever a page draws). Pure data — a value, not a namespace.
public struct PDFDocumentMetadata: Sendable {
    public var title: String?
    public var creator: String?
    public var subject: String?

    public init(title: String? = nil, creator: String? = nil, subject: String? = nil) {
        self.title = title
        self.creator = creator
        self.subject = subject
    }

    fileprivate var auxiliaryInfo: CFDictionary {
        var dict: [CFString: Any] = [:]
        if let title { dict[kCGPDFContextTitle] = title }
        if let creator { dict[kCGPDFContextCreator] = creator }
        if let subject { dict[kCGPDFContextSubject] = subject }
        return dict as CFDictionary
    }
}

public enum PDFDocumentWriterError: Error {
    /// `CGDataConsumer` could not be created over the in-memory output buffer.
    case consumerCreationFailed
    /// `CGContext` could not be created for the PDF media box.
    case contextCreationFailed
}

/// Generic multi-page PDF assembly: give it a page size and a page count, and a closure to draw
/// each page's content into a `CGContext`. Knows nothing about diagrams, findings, or stats — the
/// "layout/pagination pass" that ``CodebaseAtlasBuilder`` (in `AcaiApp`) composes rendered diagram
/// images and text pages through; reusable by any future multi-page PDF export. Pure CoreGraphics
/// (a `CGDataConsumer`-backed PDF context), so it behaves identically on macOS and iOS rather than
/// reaching for a platform-specific `NSPrintOperation`/`UIGraphicsPDFRenderer` API.
public struct PDFDocumentWriter {
    public let pageSize: CGSize
    public let metadata: PDFDocumentMetadata

    public init(pageSize: CGSize = CGSize(width: 612, height: 792), metadata: PDFDocumentMetadata = .init()) {
        self.pageSize = pageSize
        self.metadata = metadata
    }

    /// Writes `pageCount` pages, calling `drawPage(pageIndex, context)` once per page. The context
    /// handed to `drawPage` is pre-flipped to a top-left-origin, y-down space (the natural space for
    /// laying out text/images top-to-bottom) rather than CoreGraphics' native bottom-left origin.
    public func write(pageCount: Int, drawPage: (Int, CGContext) -> Void) throws -> Data {
        guard let data = CFDataCreateMutable(nil, 0), let consumer = CGDataConsumer(data: data) else {
            throw PDFDocumentWriterError.consumerCreationFailed
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata.auxiliaryInfo) else {
            throw PDFDocumentWriterError.contextCreationFailed
        }
        for pageIndex in 0..<max(pageCount, 0) {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            drawPage(pageIndex, context)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
