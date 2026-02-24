#if os(macOS)
import SwiftUI
import AppKit

/// An `NSViewRepresentable` overlay that intercepts scroll-wheel events and
/// translates them into zoom operations, zooming toward the cursor position.
struct ScrollWheelZoomHandler: NSViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScrollWheel = { [self] delta, locationInView in
            handleZoom(delta: delta, location: locationInView)
        }
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScrollWheel = { [self] delta, locationInView in
            handleZoom(delta: delta, location: locationInView)
        }
    }

    private func handleZoom(delta: CGFloat, location: CGPoint) {
        let zoomFactor: CGFloat = 1.03
        let newScale: CGFloat
        if delta > 0 {
            newScale = min(scale * pow(zoomFactor, delta), 5.0)
        } else {
            newScale = max(scale * pow(zoomFactor, delta), 0.1)
        }

        // Zoom toward the cursor position.
        // The point under the cursor in canvas-space should remain fixed.
        // canvasPoint = (screenPoint - offset) / scale
        // We want canvasPoint to remain the same after zoom:
        // canvasPoint = (screenPoint - newOffset) / newScale
        // => newOffset = screenPoint - canvasPoint * newScale
        let canvasPoint = CGPoint(
            x: (location.x - offset.x) / scale,
            y: (location.y - offset.y) / scale
        )
        let newOffset = CGPoint(
            x: location.x - canvasPoint.x * newScale,
            y: location.y - canvasPoint.y * newScale
        )

        scale = newScale
        offset = newOffset
    }

    final class ScrollWheelNSView: NSView {
        var onScrollWheel: ((CGFloat, CGPoint) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            guard let onScrollWheel else {
                super.scrollWheel(with: event)
                return
            }
            // Use scrollingDeltaY for smooth trackpad and mouse wheel.
            let delta = event.scrollingDeltaY
            guard abs(delta) > 0.01 else { return }

            let location = convert(event.locationInWindow, from: nil)
            // Flip Y coordinate (NSView has origin at bottom-left, SwiftUI at top-left).
            let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
            onScrollWheel(delta, flippedLocation)
        }

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Allow the view to receive scroll events across its entire frame.
            return frame.contains(point) ? self : nil
        }
    }
}
#endif
