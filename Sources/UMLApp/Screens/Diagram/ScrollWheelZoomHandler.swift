#if os(macOS)
import SwiftUI
@preconcurrency import AppKit

/// An `NSViewRepresentable` that installs application-level event monitors for
/// scroll-wheel zoom, trackpad pinch-to-zoom, and trackpad two-finger panning.
///
/// The embedded NSView is completely invisible to hit testing (`hitTest` returns
/// `nil`), so SwiftUI's gesture recognizers (click-drag pan, node drag, tap)
/// work unimpeded. Zoom and trackpad-pan events are intercepted via
/// `NSEvent.addLocalMonitorForEvents` which runs before AppKit dispatches
/// the events, letting us consume them without interfering with SwiftUI.
struct ScrollWheelZoomHandler: NSViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ZoomCaptureView {
        let view = ZoomCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.getState = { [self] in (scale, offset) }
        context.coordinator.setState = { [self] newScale, newOffset in
            scale = newScale
            offset = newOffset
        }
        return view
    }

    func updateNSView(_ nsView: ZoomCaptureView, context: Context) {
        context.coordinator.getState = { [self] in (scale, offset) }
        context.coordinator.setState = { [self] newScale, newOffset in
            scale = newScale
            offset = newOffset
        }
        // Keep cached geometry fresh on every SwiftUI update.
        context.coordinator.cacheGeometry(from: nsView)
    }

    // MARK: - Coordinator

    /// Always accessed on the main thread (NSViewRepresentable lifecycle +
    /// NSEvent local monitors run on main), so `@unchecked Sendable` is safe.
    final class Coordinator: @unchecked Sendable {
        var getState: (() -> (CGFloat, CGPoint))?
        var setState: ((CGFloat, CGPoint) -> Void)?

        /// Cached view geometry so event monitors can do coordinate conversion
        /// without accessing @MainActor-isolated NSView properties.
        private var cachedFrameOriginInWindow: CGPoint = .zero
        private var cachedBounds: CGRect = .zero

        private var scrollMonitor: Any?
        private var magnifyMonitor: Any?

        /// Snapshots the view's geometry for use in event monitor callbacks.
        /// Always called from @MainActor contexts (NSView lifecycle, updateNSView).
        @MainActor func cacheGeometry(from view: NSView) {
            cachedBounds = view.bounds
            let frameInWindow = view.convert(view.bounds, to: nil)
            cachedFrameOriginInWindow = frameInWindow.origin
        }

        /// Converts a point in window coordinates to the view's local coordinate
        /// system using cached geometry, then flips Y for SwiftUI (top-left origin).
        private func viewLocation(fromWindowPoint windowPoint: CGPoint) -> (inView: CGPoint, flipped: CGPoint)? {
            let local = CGPoint(
                x: windowPoint.x - cachedFrameOriginInWindow.x,
                y: windowPoint.y - cachedFrameOriginInWindow.y
            )
            guard cachedBounds.contains(local) else { return nil }
            let flipped = CGPoint(x: local.x, y: cachedBounds.height - local.y)
            return (local, flipped)
        }

        /// Installs app-level event monitors for scroll-wheel and magnify events.
        func installMonitors() {
            removeMonitors()

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                guard self.viewLocation(fromWindowPoint: event.locationInWindow) != nil else {
                    return event
                }

                if event.hasPreciseScrollingDeltas {
                    // Trackpad two-finger scroll → pan the canvas.
                    guard let (scale, offset) = self.getState?() else { return event }
                    let newOffset = CGPoint(
                        x: offset.x + event.scrollingDeltaX,
                        y: offset.y + event.scrollingDeltaY
                    )
                    self.setState?(scale, newOffset)
                    return nil // Consume the event.
                }

                // Mouse scroll wheel → zoom.
                let delta = event.scrollingDeltaY
                guard abs(delta) > 0.01 else { return event }
                guard let (_, flipped) = self.viewLocation(fromWindowPoint: event.locationInWindow) else {
                    return event
                }
                self.handleZoom(delta: delta, location: flipped)
                return nil // Consume the event.
            }

            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self else { return event }
                guard let (_, flipped) = self.viewLocation(fromWindowPoint: event.locationInWindow) else {
                    return event
                }
                self.handleMagnify(magnification: event.magnification, location: flipped)
                return nil // Consume the event.
            }
        }

        func removeMonitors() {
            if let m = scrollMonitor {
                NSEvent.removeMonitor(m)
                scrollMonitor = nil
            }
            if let m = magnifyMonitor {
                NSEvent.removeMonitor(m)
                magnifyMonitor = nil
            }
        }

        deinit {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
            if let m = magnifyMonitor { NSEvent.removeMonitor(m) }
        }

        // MARK: - Zoom Math

        func handleZoom(delta: CGFloat, location: CGPoint) {
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

        func handleMagnify(magnification: CGFloat, location: CGPoint) {
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
    }

    // MARK: - NSView

    /// Invisible NSView that serves as an anchor for the event monitors.
    /// Returns `nil` from `hitTest` so all mouse events pass straight through
    /// to SwiftUI's gesture system. Updates cached geometry on layout changes.
    final class ZoomCaptureView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil // Completely invisible to hit testing.
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                coordinator?.cacheGeometry(from: self)
                coordinator?.installMonitors()
            } else {
                coordinator?.removeMonitors()
            }
        }

        override func layout() {
            super.layout()
            // Keep cached geometry in sync when the window resizes.
            coordinator?.cacheGeometry(from: self)
        }
    }
}
#endif
