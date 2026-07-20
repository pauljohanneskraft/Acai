import XCTest

/// Accessors for a project's detail pane (`ProjectDetailView`). See `TESTING_ARCHITECTURE.md`
/// Layer 2.
final class ProjectDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var addCodebaseButton: XCUIElement { app.buttons["projectDetail.addCodebaseButton"] }
    var addDiagramButton: XCUIElement { app.buttons["projectDetail.addDiagramButton"] }

    /// `.firstMatch`, not the strict single-element subscript: this identifier can resolve to more
    /// than one accessibility node for a system-styled `.confirmationDialog` action (observed
    /// empirically, not fully root-caused — plausibly the destructive button rendering both a
    /// button and a nested label as separately-queryable elements). Any one of them performs the
    /// same tap.
    var deleteCodebaseConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "projectDetail.codebase.delete.confirmButton").firstMatch
    }

    func codebaseRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["projectDetail.codebaseRow.\(id)"]
    }
}
