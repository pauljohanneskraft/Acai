import XCTest

@MainActor
final class HotspotScreen: DiagramScreenBase {
    var hotspotList: XCUIElement { app.collectionViews.firstMatch }

    /// Matched by visible label — rows don't carry a per-file accessibility identifier.
    func hotspotRow(named fileName: String) -> XCUIElement {
        app.staticTexts[fileName]
    }

    var loadingState: XCUIElement { app.descendants(matching: .any)["hotspot.loading"].firstMatch }
    var noGitHistoryState: XCUIElement { app.descendants(matching: .any)["hotspot.noGitHistory"].firstMatch }
}
