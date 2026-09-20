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
    var historyNotFetchedState: XCUIElement {
        app.descendants(matching: .any)["hotspot.historyNotFetched"].firstMatch
    }
    var fetchFullHistoryButton: XCUIElement { app.buttons["hotspot.fullHistoryButton"].firstMatch }

    /// The state and its button go away once the history has arrived and churn is counted.
    func fetchFullHistory(file: StaticString = #filePath, line: UInt = #line) {
        fetchFullHistoryButton.tapWhenReady("Fetch Full History", file: file, line: line)
        historyNotFetchedState.waitForDisappearanceOrFail(
            "the history-not-fetched state", failingOn: app.alerts.firstMatch, file: file, line: line)
    }
}
