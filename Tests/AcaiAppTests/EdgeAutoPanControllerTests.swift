import CoreGraphics
import SwiftUI
import Testing
@testable import AcaiApp

@Suite("Edge Auto-Pan")
struct EdgeAutoPanControllerTests {
    private func controllerAtRightEdge(reducesMotion: Bool) -> EdgeAutoPanController {
        let controller = EdgeAutoPanController()
        controller.viewportSize = CGSize(width: 300, height: 600)
        controller.canvasLocation = CGPoint(x: 290, y: 300)
        controller.reducesMotion = reducesMotion
        return controller
    }

    private func deltas(from controller: EdgeAutoPanController, ticks: Int) -> [CGSize] {
        (0..<ticks).compactMap { _ in controller.nextPanDelta() }
    }

    @Test("Without Reduce Motion, every tick at the edge pans a little")
    func continuousPan() {
        let controller = controllerAtRightEdge(reducesMotion: false)
        let values = deltas(from: controller, ticks: 2)
        #expect(values.count == 2)
        #expect(values.allSatisfy { $0.width > 0 && $0.width < 10 && $0.height == 0 })
    }

    @Test("With Reduce Motion, holding at the edge jumps a third of the viewport every half second")
    func steppedPan() {
        let controller = controllerAtRightEdge(reducesMotion: true)
        var values = deltas(from: controller, ticks: 29)
        #expect(values.isEmpty)
        values += deltas(from: controller, ticks: 1)
        #expect(values == [CGSize(width: 100, height: 0)])
        values += deltas(from: controller, ticks: 30)
        #expect(values.count == 2)
    }

    @Test("With Reduce Motion, leaving the edge restarts the wait before the next jump")
    func steppedPanResetsAwayFromEdge() {
        let controller = controllerAtRightEdge(reducesMotion: true)
        var values = deltas(from: controller, ticks: 20)
        controller.canvasLocation = CGPoint(x: 150, y: 300)
        values += deltas(from: controller, ticks: 1)
        controller.canvasLocation = CGPoint(x: 290, y: 300)
        values += deltas(from: controller, ticks: 29)
        #expect(values.isEmpty)
    }

    @Test("Stopping a pan releases the canvas state the tick handler captured")
    func stoppingReleasesTheCapturedCanvas() {
        weak var leaked: EdgeAutoPanController?

        do {
            let storage = CanvasStorage()
            leaked = storage.controller
            storage.controller.viewportSize = CGSize(width: 300, height: 600)
            storage.controller.canvasLocation = CGPoint(x: 290, y: 300)
            storage.controller.start { canvasDelta in storage.offset.width -= canvasDelta.width }

            storage.controller.tick()
            #expect(storage.offset.width < 0, "the handler passed to start() should drive the pan")

            storage.controller.stop()
        }

        #expect(leaked == nil)
    }

    @Test("A curve respecting Reduce Motion becomes no animation")
    func animationRespectsReduceMotion() {
        #expect(Animation.canvasPan.respecting(reduceMotion: true) == nil)
        #expect(Animation.canvasPan.respecting(reduceMotion: false) == .canvasPan)
    }
}

/// Stands in for the SwiftUI `@State` storage a canvas keeps its controller in: the handler the
/// canvas installs writes back through state that owns the controller, so a handler outliving the
/// pan is a retain cycle.
private final class CanvasStorage {
    let controller = EdgeAutoPanController()
    var offset: CGSize = .zero
}
