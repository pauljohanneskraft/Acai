import CoreGraphics

/// The canvas offset that brings a canvas-space rect into view at the current zoom.
struct CanvasCentering {
    let viewport: CGSize
    let scale: CGFloat

    func offset(centring rect: CGRect) -> CGPoint {
        CGPoint(x: viewport.width / 2 - rect.midX * scale, y: viewport.height / 2 - rect.midY * scale)
    }

    /// `current` while `rect` is already fully on screen, so a jump between visible elements doesn't pan.
    func offset(revealing rect: CGRect, from current: CGPoint) -> CGPoint {
        guard viewport.width > 0, viewport.height > 0, scale > 0 else { return current }
        let visible = CGRect(
            x: -current.x / scale, y: -current.y / scale, width: viewport.width / scale, height: viewport.height / scale
        )
        return visible.contains(rect) ? current : offset(centring: rect)
    }
}
