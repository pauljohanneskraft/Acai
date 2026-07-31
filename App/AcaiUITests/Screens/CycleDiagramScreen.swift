import XCTest

/// Accessors for the Cycle Diagram (`CycleDiagramView`) — reached via `ViolationRowView`'s "View
/// as Diagram" action on a Quality Check cycle violation row, then this screen's own (shared
/// `DiagramScreenBase`) sidebar toggle for the member/dependency list.
@MainActor
final class CycleDiagramScreen: DiagramScreenBase {
    /// `ViolationRowView`'s entry point into this diagram, tapped from the Quality Check report
    /// (only present on a `cycle`-kind violation row).
    var viewAsDiagramButton: XCUIElement { app.buttons["violation.viewAsDiagramButton"] }

    /// The member/dependency list, shown in the sidebar/inspector once `sidebarToggleButton` is
    /// tapped — the accessible, non-visual restatement of the loop layout.
    var memberDependencyList: XCUIElement { app.collectionViews.firstMatch }

    /// A member row by its label (type qualified-name or module name).
    func memberRow(named label: String) -> XCUIElement {
        app.staticTexts[label]
    }
}
