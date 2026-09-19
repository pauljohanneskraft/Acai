import CoreGraphics
import SwiftUI
import Testing
@testable import AcaiApp

@Suite("Edge Auto-Pan")
struct EdgeAutoPanControllerTests {
    private func controllerAtRightEdge(reducesMotion: Bool) -> (EdgeAutoPanController, Deltas) {
        let controller = EdgeAutoPanController()
        controller.viewportSize = CGSize(width: 300, height: 600)
        controller.canvasLocation = CGPoint(x: 290, y: 300)
        controller.reducesMotion = reducesMotion
        let deltas = Deltas()
        controller.onPanTick = { deltas.values.append($0) }
        return (controller, deltas)
    }

    @Test("Without Reduce Motion, every tick at the edge pans a little")
    func continuousPan() {
        let (controller, deltas) = controllerAtRightEdge(reducesMotion: false)
        controller.tick()
        controller.tick()
        #expect(deltas.values.count == 2)
        #expect(deltas.values.allSatisfy { $0.width > 0 && $0.width < 10 && $0.height == 0 })
    }

    @Test("With Reduce Motion, holding at the edge jumps a third of the viewport every half second")
    func steppedPan() {
        let (controller, deltas) = controllerAtRightEdge(reducesMotion: true)
        for _ in 0..<29 { controller.tick() }
        #expect(deltas.values.isEmpty)
        controller.tick()
        #expect(deltas.values == [CGSize(width: 100, height: 0)])
        for _ in 0..<30 { controller.tick() }
        #expect(deltas.values.count == 2)
    }

    @Test("With Reduce Motion, leaving the edge restarts the wait before the next jump")
    func steppedPanResetsAwayFromEdge() {
        let (controller, deltas) = controllerAtRightEdge(reducesMotion: true)
        for _ in 0..<20 { controller.tick() }
        controller.canvasLocation = CGPoint(x: 150, y: 300)
        controller.tick()
        controller.canvasLocation = CGPoint(x: 290, y: 300)
        for _ in 0..<29 { controller.tick() }
        #expect(deltas.values.isEmpty)
    }

    @Test("A curve respecting Reduce Motion becomes no animation")
    func animationRespectsReduceMotion() {
        #expect(Animation.canvasPan.respecting(reduceMotion: true) == nil)
        #expect(Animation.canvasPan.respecting(reduceMotion: false) == .canvasPan)
    }
}

private final class Deltas {
    var values: [CGSize] = []
}
