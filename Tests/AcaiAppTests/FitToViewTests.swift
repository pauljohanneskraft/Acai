import CoreGraphics
import Testing
@testable import AcaiApp

@Suite("FitToView")
@MainActor
struct FitToViewTests {
    private let rects: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 100, height: 80),
        "b": CGRect(x: 400, y: 300, width: 100, height: 80)
    ]

    private func fit(viewport: CGSize) -> FitToView {
        FitToView(nodeIDs: ["a", "b"], rect: { rects[$0] }, viewport: viewport)
    }

    @Test func framesAllNodesInsideALaidOutViewport() throws {
        let viewport = CGSize(width: 1000, height: 800)
        let fitting = fit(viewport: viewport)
        let transform = try #require(fitting.transform)
        let bounds = rects.values.reduce(CGRect.null) { $0.union($1) }
        let framed = CGRect(
            x: bounds.minX * transform.scale + transform.offset.x,
            y: bounds.minY * transform.scale + transform.offset.y,
            width: bounds.width * transform.scale,
            height: bounds.height * transform.scale
        )
        let padded = CGRect(origin: .zero, size: viewport).insetBy(dx: fitting.padding, dy: fitting.padding)
        #expect(padded.contains(framed))
        #expect(abs(framed.midX - viewport.width / 2) < 0.001)
        #expect(abs(framed.midY - viewport.height / 2) < 0.001)
    }

    @Test func declinesAViewportThatHasNotBeenLaidOutYet() {
        #expect(fit(viewport: .zero).transform == nil)
        #expect(fit(viewport: CGSize(width: 100, height: 100)).transform == nil)
    }

    @Test func declinesWhenNoNodeHasARect() {
        #expect(FitToView(nodeIDs: ["missing"], rect: { _ in nil }).transform == nil)
    }
}
