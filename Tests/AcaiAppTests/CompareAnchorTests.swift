import CoreGraphics
import Testing
@testable import AcaiApp

@Suite("Compare anchor")
struct CompareAnchorTests {
    private let host = CGRect(x: 200, y: 50, width: 900, height: 700)
    private let button = CGRect(x: 1020, y: 96, width: 44, height: 44)

    private func anchored() -> CompareAnchor {
        var anchor = CompareAnchor()
        anchor.update(host: host)
        anchor.update(button: button)
        return anchor
    }

    @Test func hasNoPlacementUntilBothTheHostAndTheButtonHaveReported() {
        var anchor = CompareAnchor()
        #expect(anchor.placement == nil)

        anchor.update(host: host)
        #expect(anchor.placement == nil)

        anchor.update(button: button)
        #expect(anchor.placement == CGRect(x: 820, y: 46, width: 44, height: 44))
    }

    @Test func ignoresTheEmptyFrameARebuiltViewReportsBeforeItsFirstLayout() {
        var anchor = anchored()
        let placement = anchor.placement

        anchor.update(button: .zero)
        anchor.update(host: .zero)

        #expect(anchor.placement == placement)
    }

    @Test func holdsStillWhileThePanelIsOpen() {
        var anchor = anchored()
        let placement = anchor.placement

        anchor.holdStill(true)
        anchor.update(button: button.offsetBy(dx: 0, dy: 300))
        anchor.update(host: host.offsetBy(dx: 0, dy: 100))

        #expect(anchor.placement == placement)
    }

    @Test func followsTheButtonWhileThePanelIsClosed() {
        var anchor = anchored()

        anchor.update(button: button.offsetBy(dx: -120, dy: 0))

        #expect(anchor.placement == CGRect(x: 700, y: 46, width: 44, height: 44))
    }

    @Test func takesTheFrameTheButtonMovedToWhileOpenOnceThePanelCloses() {
        var anchor = anchored()

        anchor.holdStill(true)
        anchor.update(button: button.offsetBy(dx: -300, dy: 0))
        anchor.holdStill(false)

        #expect(anchor.placement == CGRect(x: 520, y: 46, width: 44, height: 44))
    }

    @Test func holdsTheFirstPlacementWhenOpenedBeforeTheFramesWereKnown() {
        var anchor = CompareAnchor()

        anchor.holdStill(true)
        anchor.update(host: host)
        anchor.update(button: button)
        anchor.update(button: button.offsetBy(dx: 0, dy: 300))

        #expect(anchor.placement == CGRect(x: 820, y: 46, width: 44, height: 44))
    }
}
