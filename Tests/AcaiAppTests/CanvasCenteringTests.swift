import CoreGraphics
import Testing
@testable import AcaiApp

@Suite("Canvas centring")
struct CanvasCenteringTests {
    private let centering = CanvasCentering(viewport: CGSize(width: 800, height: 600), scale: 2)

    @Test("The offset puts the rect's centre at the viewport's centre")
    func centresTheRect() {
        let rect = CGRect(x: 1000, y: 500, width: 100, height: 40)

        let offset = centering.offset(centring: rect)

        #expect(rect.midX * 2 + offset.x == 400)
        #expect(rect.midY * 2 + offset.y == 300)
    }

    @Test("A rect already on screen keeps the current offset; one off screen is centred")
    func revealsOnlyWhatIsOffScreen() {
        let current = CGPoint(x: -100, y: -100)
        let visible = CGRect(x: 100, y: 100, width: 50, height: 50)
        let offScreen = CGRect(x: 3000, y: 3000, width: 50, height: 50)

        #expect(centering.offset(revealing: visible, from: current) == current)
        #expect(centering.offset(revealing: offScreen, from: current) == centering.offset(centring: offScreen))
    }

    @Test("Before the viewport is laid out the offset stays put")
    func ignoresAnUnmeasuredViewport() {
        let unmeasured = CanvasCentering(viewport: .zero, scale: 1)

        #expect(unmeasured.offset(revealing: CGRect(x: 5000, y: 5000, width: 10, height: 10), from: .zero) == .zero)
    }
}
