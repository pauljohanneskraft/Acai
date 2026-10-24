import CoreGraphics
import Testing
@testable import AcaiApp

@Suite("Compare anchor")
struct CompareAnchorTests {
    private let host = CGRect(x: 200, y: 50, width: 900, height: 700)
    private let button = CGRect(x: 1020, y: 96, width: 44, height: 44)

    private func anchored() -> CompareAnchor {
        var anchor = CompareAnchor()
        anchor.update(host: host, isPanelPresented: false)
        anchor.update(button: button, isPanelPresented: false)
        return anchor
    }

    @Test func hasNoPlacementUntilBothTheHostAndTheButtonHaveReported() {
        var anchor = CompareAnchor()
        #expect(anchor.placement == nil)

        anchor.update(host: host, isPanelPresented: false)
        #expect(anchor.placement == nil)

        anchor.update(button: button, isPanelPresented: false)
        #expect(anchor.placement == CGRect(x: 820, y: 46, width: 44, height: 44))
    }

    @Test func ignoresTheEmptyFrameARebuiltViewReportsBeforeItsFirstLayout() {
        var anchor = anchored()
        let placement = anchor.placement

        anchor.update(button: .zero, isPanelPresented: false)
        anchor.update(host: .zero, isPanelPresented: false)

        #expect(anchor.placement == placement)
    }

    @Test func holdsStillWhileThePanelIsOpen() {
        var anchor = anchored()
        let placement = anchor.placement

        anchor.update(button: button.offsetBy(dx: 0, dy: 300), isPanelPresented: true)
        anchor.update(host: host.offsetBy(dx: 0, dy: 300), isPanelPresented: true)

        #expect(anchor.placement == placement)
    }

    @Test func followsTheButtonOnceThePanelCloses() {
        var anchor = anchored()

        anchor.update(button: button.offsetBy(dx: -120, dy: 0), isPanelPresented: false)

        #expect(anchor.placement == CGRect(x: 700, y: 46, width: 44, height: 44))
    }
}
