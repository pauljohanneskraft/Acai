#if os(macOS)
import SwiftUI
import AppKit

/// An `NSViewRepresentable` that monitors scroll-wheel and trackpad pinch
/// (magnify) events for zoom, without interfering with SwiftUI's gesture
/// handling (panning, dragging nodes, clicking).
///
/// Uses `NSEvent.addLocalMonitorForEvents` so the overlay doesn't need to
/// participate in hit testing at all.
struct ScrollWheelZoomHandler: NSViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = ZoomAnchorView()
        view.coordinator = context.coordinator
        context.coordinator.anchorView = view
        context.coordinator.getState = { [self] in (scale, offset) }
        context.coordinator.setState = { [self] newScale, newOffset in
            scale = newScale
            offset = newOffset
        }
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.getState = { [self] in (scale, offset) }
        context.coordinator.setState = { [self] newScale, newOffset in
            scale = newScale
            offset = newOffset
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        weak var anchorView: NSView?
        var getState: (() -> (CGFloat, CGPoint))?
        var setState: ((CGFloat, CGPoint) -> Void)?
        private var scrollMonitor: Any?
        private var magnifyMonitor: Any?

        func startMonitoring() {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.anchorView else { return event }
                // Only handle if the cursor is within our view.
                let locationInView = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(locationInView) else { return event }

                // On trackpad, two-finger scroll = panning (let SwiftUI handle it).
                if event.hasPreciseScrollingDeltas {
                    return event
                }

                // Mouse scroll wheel = zoom.
                let delta = event.scrollingDeltaY
                guard abs(delta) > 0.01 else { return event }
                let flipped = CGPoint(x: locationInView.x, y: view.bounds.height - locationInView.y)
                self.handleZoom(delta: delta, location: flipped)
                return nil // consume the event
            }

            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, let view = self.anchorView else { return event }
                let locationInView = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(locationInView) else { return event }

                let flipped = CGPoint(x: locationInView.x, y: view.bounds.height - locationInView.y)
                self.handleMagnify(magnification: event.magnification, location: flipped)
                return nil // consume the event
            }
        }

        func stopMonitoring() {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
            scrollMonitor = nil
            magnifyMonitor = nil
        }

        private func handleZoom(delta: CGFloat, location: CGPoint) {
            guard let (scale, offset) = getState?() else { return }
            let zoomFactor: CGFloat = 1.03
            let newScale: CGFloat
            if delta > 0 {
                newScale = min(scale * pow(zoomFactor, delta), 5.0)
            } else {
                newScale = max(scale * pow(zoomFactor, delta), 0.1)
            }

            let canvasPoint = CGPoint(
                x: (location.x - offset.x) / scale,
                y: (location.y - offset.y) / scale
            )
            let newOffset = CGPoint(
                x: location.x - canvasPoint.x * newScale,
                y: location.y - canvasPoint.y * newScale
            )
            setState?(newScale, newOffset)
        }

        private func handleMagnify(magnification: CGFloat, location: CGPoint) {
            guard let (scale, offset) = getState?() else { return }
            let newScale = max(0.1, min(5.0, scale * (1.0 + magnification)))

            let canvasPoint = CGPoint(
                x: (location.x - offset.x) / scale,
                y: (location.y - offset.y) / scale
            )
            let newOffset = CGPoint(
                x: location.x - canvasPoint.x * newScale,
                y: location.y - canvasPoint.y * newScale
            )
            setState?(newScale, newOffset)
        }

        deinit {
            stopMonitoring()
        }
    }

    /// A transparent NSView used solely as a coordinate reference for
    /// converting event locations. Does not participate in hit testing.
    final class ZoomAnchorView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Never intercept hit testing — let SwiftUI handle all clicks/drags.
            return nil
        }
    }
}
#endif
