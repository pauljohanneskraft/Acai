import CoreGraphics
import Testing
@testable import AcaiApp

@Suite("Compare anchor")
struct CompareAnchorTests {
    private let button = CGRect(x: 820, y: 96, width: 44, height: 44)

    @Test func isUnresolvedUntilTheButtonReportsAFrame() {
        var anchor = CompareAnchor()
        #expect(!anchor.isResolved)

        anchor.update(to: button, isPanelPresented: false)

        #expect(anchor.isResolved)
        #expect(anchor.frame == button)
    }

    @Test func ignoresTheEmptyFrameARebuiltButtonReportsBeforeItsFirstLayout() {
        var anchor = CompareAnchor()
        anchor.update(to: button, isPanelPresented: false)

        anchor.update(to: .zero, isPanelPresented: false)

        #expect(anchor.frame == button)
    }

    @Test func holdsStillWhileThePanelIsOpen() {
        var anchor = CompareAnchor()
        anchor.update(to: button, isPanelPresented: false)

        anchor.update(to: button.offsetBy(dx: 0, dy: 300), isPanelPresented: true)

        #expect(anchor.frame == button)
    }

    @Test func takesTheButtonsNewPlaceOnceThePanelCloses() {
        var anchor = CompareAnchor()
        anchor.update(to: button, isPanelPresented: false)
        let moved = button.offsetBy(dx: -120, dy: 0)

        anchor.update(to: moved, isPanelPresented: false)

        #expect(anchor.frame == moved)
    }
}
