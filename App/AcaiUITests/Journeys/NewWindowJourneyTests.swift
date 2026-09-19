#if os(macOS)
import XCTest

/// A diagram opens in a window of its own, and is never shown by two windows at once.
@MainActor
final class NewWindowJourneyTests: UIJourneyTestCase {
    private let freeformDiagramID = "33333333-3333-3333-3333-333333333333"

    func testADiagramInItsOwnWindowIsBroughtForwardRatherThanShownTwice() {
        let detail = openSeededProject()

        detail.openFreeformDiagramInNewWindow(id: freeformDiagramID)
        XCTAssertEqual(app.windows.count, 2, "Open in New Window must add a window, not replace the first.")

        // The new window opens in front, covering the first one.
        ProjectBrowserScreen(app: app).cycleWindows()
        let row = detail.freeformDiagramRow(id: freeformDiagramID)
        row.tapWhenReady("the freeform diagram's row in the first window")
        let showWindow = app.buttons["diagramOpenElsewhere.showWindowButton"]
        showWindow.waitOrFail("the placeholder for a diagram another window shows")

        showWindow.tapWhenReady("Show Window")
        app.windows.firstMatch.descendants(matching: .any)["diagram.checkpointsButton"]
            .waitOrFail("the diagram's own window, brought to the front")
        XCTAssertEqual(app.windows.count, 2, "Show Window must focus the existing window, not open another.")
    }
}
#endif
