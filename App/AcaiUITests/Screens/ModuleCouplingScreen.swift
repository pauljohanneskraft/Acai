import XCTest

@MainActor
final class ModuleCouplingScreen: DiagramScreenBase {
    var legendList: XCUIElement { app.collectionViews.firstMatch }

    /// Matched by visible label — rows don't carry a per-module accessibility identifier.
    func legendRow(named name: String) -> XCUIElement {
        app.staticTexts[name]
    }
}
