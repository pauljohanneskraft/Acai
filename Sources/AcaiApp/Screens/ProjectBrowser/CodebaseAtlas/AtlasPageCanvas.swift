import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Draws one Atlas PDF page's content into an already-flipped (top-left origin, y-down) `CGContext`
/// — single lines of CoreText-laid-out text advancing a running cursor, plus one aspect-fit image.
/// Pure CoreGraphics/CoreText, so it draws identically on macOS and iOS; knows nothing about
/// `Finding`/`CodeMetrics`/`GeneratedDiagram` — ``CodebaseAtlasBuilder`` owns turning those into the
/// strings and images handed here. A value you instantiate per page, not a namespace.
struct AtlasPageCanvas {
    let context: CGContext
    let bounds: CGRect
    private var cursorY: CGFloat

    init(context: CGContext, bounds: CGRect) {
        self.context = context
        self.bounds = bounds
        self.cursorY = bounds.minY
    }

    /// Remaining vertical space below the cursor.
    var remainingHeight: CGFloat { bounds.maxY - cursorY }

    /// Draws one line of text at the current cursor and advances it by the line's height plus
    /// `spacing`. Long text is truncated with an ellipsis to the page's width rather than wrapped —
    /// the Atlas's findings/stats entries are one line each by design.
    mutating func drawLine(_ text: String, fontSize: CGFloat, bold: Bool = false, spacing: CGFloat = 6) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, fontSize, nil)
        let fontKey = kCTFontAttributeName as NSAttributedString.Key
        let attributed = NSAttributedString(string: text, attributes: [fontKey: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let ellipsis = NSAttributedString(string: "…", attributes: [fontKey: font])
        let truncationToken = CTLineCreateWithAttributedString(ellipsis)
        let fitted = CTLineCreateTruncatedLine(line, bounds.width, .end, truncationToken) ?? line

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(fitted, &ascent, &descent, &leading)
        let lineHeight = ascent + descent + leading
        // A page's content is bounded by `bounds` (never re-flowed onto a new page from in here —
        // `CodebaseAtlasBuilder` owns pagination); a line that would run past the bottom margin is
        // dropped rather than silently drawn off-page. In practice this only bites a hand-picked
        // `itemsPerPage` that undercounts what the page actually fits, not real content, since every
        // caller already paginates to its own budget.
        guard lineHeight <= remainingHeight else { return }

        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.textMatrix = .identity
        // `CTLineDraw` draws in a bottom-up text space, so translate to the line's baseline (the
        // cursor plus the ascent) within this already-flipped, y-down page context, then flip the
        // local space back so the glyphs paint right-side up instead of mirrored.
        context.translateBy(x: bounds.minX, y: cursorY + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(fitted, context)
        context.restoreGState()

        cursorY += lineHeight + spacing
    }

    /// Draws `image`, scaled to fit within the remaining page bounds while preserving its aspect
    /// ratio, centred horizontally.
    mutating func drawImage(_ image: CGImage) {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0, remainingHeight > 0 else { return }
        let scale = min(bounds.width / imageSize.width, remainingHeight / imageSize.height, 1)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: bounds.minX + (bounds.width - fittedSize.width) / 2, y: cursorY)
        let rect = CGRect(origin: origin, size: fittedSize)

        // `CGContext.draw(_:in:)` draws image data bottom-up; this page context is already flipped
        // to y-down for text, so flip locally back to CoreGraphics' native orientation just for the
        // image draw, otherwise it paints upside down.
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY + rect.minY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()

        cursorY += fittedSize.height
    }
}

extension Data {
    /// Decodes PNG (or any ImageIO-readable) bytes to a `CGImage`, `nil` if the data isn't a
    /// decodable image.
    var cgImage: CGImage? {
        guard let source = CGImageSourceCreateWithData(self as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
