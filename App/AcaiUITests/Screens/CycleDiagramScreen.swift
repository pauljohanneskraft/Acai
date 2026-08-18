import XCTest

@MainActor
final class CycleDiagramScreen: DiagramScreenBase {
    /// Only present on a `cycle`-kind violation row in the Quality Check report.
    var viewAsDiagramButton: XCUIElement { app.buttons["violation.viewAsDiagramButton"] }

    var memberDependencyList: XCUIElement { app.collectionViews.firstMatch }

    /// By its label (type qualified-name or module name).
    func memberRow(named label: String) -> XCUIElement {
        app.staticTexts[label]
    }
}
