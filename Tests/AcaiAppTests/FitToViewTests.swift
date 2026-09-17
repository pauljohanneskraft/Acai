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
        let transform = try #require(fit(viewport: CGSize(width: 1000, height: 800)).transform)
        #expect(transform.scale > FitToView(nodeIDs: [], rect: { _ in nil }).minScale)
        #expect(transform.scale <= FitToView(nodeIDs: [], rect: { _ in nil }).maxScale)
    }

    @Test func declinesAViewportThatHasNotBeenLaidOutYet() {
        #expect(fit(viewport: .zero).transform == nil)
        #expect(fit(viewport: CGSize(width: 100, height: 100)).transform == nil)
    }

    @Test func declinesWhenNoNodeHasARect() {
        #expect(FitToView(nodeIDs: ["missing"], rect: { _ in nil }).transform == nil)
    }
}
