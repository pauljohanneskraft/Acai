import Foundation
import CoreGraphics

/// Timer-driven controller that auto-pans an infinite canvas when a drag reaches near the
/// viewport edges. A 60 Hz timer is needed because `DragGesture.onChanged` only fires on cursor
/// movement, so it goes quiet if the drag holds still at the edge. Speed increases the further
/// past the edge margin the cursor is, uncapped, like text editors accelerating on far drags.
final class EdgeAutoPanController: @unchecked Sendable {
    private var timer: Timer?

    // MARK: - Input State

    /// Current canvas-space location of the active drag.
    var canvasLocation: CGPoint = .zero

    /// Current canvas scale.
    var scale: CGFloat = 1

    /// Current canvas offset (screen-space).
    var offset: CGPoint = .zero

    /// Size of the viewport in screen points.
    var viewportSize: CGSize = .zero

    // MARK: - Output

    /// Called each tick with the *incremental* canvas delta for this frame.
    /// Use this to move all selected nodes by the delta.
    var onPanTick: ((_ canvasDelta: CGSize) -> Void)?

    // MARK: - Configuration

    /// How close (in screen points) to the viewport edge before panning begins.
    private let edgeMargin: CGFloat = 50

    /// Base pan speed (screen points per tick) at the edge boundary.
    private let basePanSpeed: CGFloat = 8

    // MARK: - Lifecycle

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Tick

    private func tick() {
        let screenX = canvasLocation.x * scale + offset.x
        let screenY = canvasLocation.y * scale + offset.y

        let w = viewportSize.width
        let h = viewportSize.height
        guard w > 0, h > 0 else { return }

        var dx: CGFloat = 0
        var dy: CGFloat = 0

        if screenX < edgeMargin {
            let depth = edgeMargin - screenX
            dx = basePanSpeed * (depth / edgeMargin)
        } else if screenX > w - edgeMargin {
            let depth = screenX - (w - edgeMargin)
            dx = -basePanSpeed * (depth / edgeMargin)
        }

        if screenY < edgeMargin {
            let depth = edgeMargin - screenY
            dy = basePanSpeed * (depth / edgeMargin)
        } else if screenY > h - edgeMargin {
            let depth = screenY - (h - edgeMargin)
            dy = -basePanSpeed * (depth / edgeMargin)
        }

        guard dx != 0 || dy != 0 else { return }

        // Update internal offset so next tick's screen conversion is accurate.
        offset.x += dx
        offset.y += dy

        let canvasDelta = CGSize(width: -dx / scale, height: -dy / scale)

        // Move canvasLocation by the same amount so the node tracks the pan.
        canvasLocation.x += canvasDelta.width
        canvasLocation.y += canvasDelta.height

        onPanTick?(canvasDelta)
    }
}
