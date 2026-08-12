import XCTest

/// Accessors for the Module Coupling chart (`ModuleCouplingChartView`) — a read-only analysis
/// screen, so beyond the shared `DiagramScreenBase` chrome (sidebar toggle/done) this only exposes
/// the legend list's rows.
@MainActor
final class ModuleCouplingScreen: DiagramScreenBase {
    /// The ranked legend list, shown in the sidebar/inspector once `sidebarToggleButton` is tapped.
    var legendList: XCUIElement { app.collectionViews.firstMatch }

    /// A legend row by module name (e.g. `"AcaiCore"`), matched by its visible label since rows
    /// don't carry a per-module accessibility identifier.
    func legendRow(named name: String) -> XCUIElement {
        app.staticTexts[name]
    }
}
