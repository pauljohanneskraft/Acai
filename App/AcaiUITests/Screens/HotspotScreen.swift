import XCTest

/// Accessors for the Hotspot chart (`HotspotChartView`) — a read-only analysis screen built on an
/// asynchronous churn load, so beyond the shared `DiagramScreenBase` chrome this exposes the
/// loading/empty-state text and the ranked hotspot list's rows.
@MainActor
final class HotspotScreen: DiagramScreenBase {
    /// The ranked hotspot list, shown in the sidebar/inspector once `sidebarToggleButton` is tapped.
    var hotspotList: XCUIElement { app.collectionViews.firstMatch }

    /// A hotspot row by file name, matched by its visible label since rows don't carry a
    /// per-file accessibility identifier.
    func hotspotRow(named fileName: String) -> XCUIElement {
        app.staticTexts[fileName]
    }

    /// Shown while `HotspotViewModel` is walking commit history off the main actor.
    var loadingIndicator: XCUIElement { app.staticTexts["Walking commit history…"] }
}
