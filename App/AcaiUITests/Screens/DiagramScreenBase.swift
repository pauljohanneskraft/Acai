import XCTest

/// Accessors for the chrome that's actually common across every diagram type's toolbar today
/// (`UndoRedoToolbarButtons`, Fit to View, the sidebar toggle) — see `TESTING_ARCHITECTURE.md`
/// Layer 2 for why this deliberately stays narrow rather than a full unified sidebar-tab base
/// class: `USABILITY_IMPROVEMENTS.md` Part 6 documents that today's diagram types have three
/// genuinely different sidebar architectures, so a shared Settings/Inspector/Compare accessor set
/// would encode a unification that hasn't shipped yet.
class DiagramScreenBase {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var undoButton: XCUIElement { app.buttons["diagram.undoButton"] }
    var redoButton: XCUIElement { app.buttons["diagram.redoButton"] }
    var fitToViewButton: XCUIElement { app.buttons["diagram.fitToViewButton"] }
    var sidebarToggleButton: XCUIElement { app.buttons["diagram.sidebarToggleButton"] }
}
