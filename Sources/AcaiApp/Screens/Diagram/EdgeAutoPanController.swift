import Foundation
import CoreGraphics

/// Timer-driven controller that auto-pans an infinite canvas when a drag reaches near the
/// viewport edges. A 60 Hz timer is needed because `DragGesture.onChanged` only fires on cursor
/// movement, so it goes quiet if the drag holds still at the edge. Speed increases the further
/// past the edge margin the cursor is, uncapped, like text editors accelerating on far drags.
final class EdgeAutoPanController: @unchecked Sendable {
    private var timer: Timer?

    // MARK: - Input State

    /// Canvas-space (not screen-space).
    var canvasLocation: CGPoint = .zero

    var scale: CGFloat = 1

    /// Screen-space (not canvas-space).
    var offset: CGPoint = .zero

    var viewportSize: CGSize = .zero

    /// Replaces the continuous scroll with a jump of a third of the viewport every half second.
    var reducesMotion = false

    // MARK: - Output

    /// Called each tick with the *incremental* canvas delta for this frame.
    var onPanTick: ((_ canvasDelta: CGSize) -> Void)?

    // MARK: - Configuration

    private let edgeMargin: CGFloat = 50

    private let basePanSpeed: CGFloat = 8

    private let ticksPerStep = 30

    private lazy var ticksUntilStep = ticksPerStep

    // MARK: - Lifecycle

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        ticksUntilStep = ticksPerStep
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

    func tick() {
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

        guard dx != 0 || dy != 0 else {
            ticksUntilStep = ticksPerStep
            return
        }

        if reducesMotion {
            ticksUntilStep -= 1
            guard ticksUntilStep <= 0 else { return }
            ticksUntilStep = ticksPerStep
            dx = dx == 0 ? 0 : (dx > 0 ? w : -w) / 3
            dy = dy == 0 ? 0 : (dy > 0 ? h : -h) / 3
        }

        // Keep the internal offset in sync so the next tick's screen conversion stays accurate.
        offset.x += dx
        offset.y += dy

        let canvasDelta = CGSize(width: -dx / scale, height: -dy / scale)

        // Also move canvasLocation so the dragged node keeps tracking the pan.
        canvasLocation.x += canvasDelta.width
        canvasLocation.y += canvasDelta.height

        onPanTick?(canvasDelta)
    }
}
