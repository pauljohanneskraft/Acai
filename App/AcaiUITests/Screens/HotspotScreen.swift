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
    var errorState: XCUIElement { app.descendants(matching: .any)["hotspot.error"].firstMatch }
    var retryButton: XCUIElement { app.buttons["hotspot.retryButton"].firstMatch }
    var reload: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "hotspot.reload") }

    /// Observed through the reload's own status rather than the error state disappearing: a retry
    /// that hits the same failure leaves that state exactly where it was.
    func retry(file: StaticString = #filePath, line: UInt = #line) {
        retryButton.tapWhenReady("Retry", file: file, line: line)
        reload.waitUntilLoaded("Reloading the hotspot chart", file: file, line: line)
    }

    /// The state and its button go away once the history has arrived and churn is counted.
    func fetchFullHistory(file: StaticString = #filePath, line: UInt = #line) {
        fetchFullHistoryButton.tapWhenReady("Fetch Full History", file: file, line: line)
        historyNotFetchedState.waitForDisappearanceOrFail(
            "the history-not-fetched state", failingOn: app.alerts.firstMatch, file: file, line: line)
    }
}
