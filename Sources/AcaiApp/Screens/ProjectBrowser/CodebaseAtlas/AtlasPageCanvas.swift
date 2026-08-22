import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Draws into an already-flipped (top-left origin, y-down) `CGContext`. Knows nothing about
/// `Finding`/`CodeMetrics`/`GeneratedDiagram` — `CodebaseAtlasBuilder` owns turning those into the
/// strings and images handed here.
struct AtlasPageCanvas {
    let context: CGContext
    let bounds: CGRect
    private var cursorY: CGFloat

    init(context: CGContext, bounds: CGRect) {
        self.context = context
        self.bounds = bounds
        self.cursorY = bounds.minY
    }

    var remainingHeight: CGFloat { bounds.maxY - cursorY }

    /// Truncates to the page width with an ellipsis rather than wrapping — the Atlas's findings/stats
    /// entries are one line each by design.
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
        // A line that would run past the bottom margin is dropped rather than drawn off-page;
        // pagination itself is CodebaseAtlasBuilder's job, not this canvas's.
        guard lineHeight <= remainingHeight else { return }

        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.textMatrix = .identity
        // CTLineDraw expects bottom-up text space; translate to the baseline and flip locally so
        // glyphs paint right-side up in this y-down page context.
        context.translateBy(x: bounds.minX, y: cursorY + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(fitted, context)
        context.restoreGState()

        cursorY += lineHeight + spacing
    }

    mutating func drawImage(_ image: CGImage) {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0, remainingHeight > 0 else { return }
        let scale = min(bounds.width / imageSize.width, remainingHeight / imageSize.height, 1)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: bounds.minX + (bounds.width - fittedSize.width) / 2, y: cursorY)
        let rect = CGRect(origin: origin, size: fittedSize)

        // CGContext.draw(_:in:) draws image data bottom-up; flip locally or it paints upside down.
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY + rect.minY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()

        cursorY += fittedSize.height
    }
}

extension Data {
    var cgImage: CGImage? {
        guard let source = CGImageSourceCreateWithData(self as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
