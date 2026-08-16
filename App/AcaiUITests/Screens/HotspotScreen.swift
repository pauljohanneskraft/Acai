import XCTest

@MainActor
final class HotspotScreen: DiagramScreenBase {
    var hotspotList: XCUIElement { app.collectionViews.firstMatch }

    /// Matched by visible label — rows don't carry a per-file accessibility identifier.
    func hotspotRow(named fileName: String) -> XCUIElement {
        app.staticTexts[fileName]
    }

    var loadingIndicator: XCUIElement { app.staticTexts["Walking commit history…"] }
}
