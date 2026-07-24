import XCTest

/// Accessors for `NewProjectSheet`, reached via `ProjectBrowserScreen.newProjectButton`.
/// See `TESTING_ARCHITECTURE.md` Layer 2.
final class NewProjectSheetScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var titleField: XCUIElement { app.textFields["newProjectSheet.titleField"] }
    var subtitleField: XCUIElement { app.textFields["newProjectSheet.subtitleField"] }
    /// `.firstMatch`: a toolbar button's identifier resolves to more than one accessibility node
    /// (the wrapping bar-item container and the nested button both carry it) — same class of issue
    /// as `ProjectDetailScreen.deleteCodebaseConfirmButton`, confirmed empirically for
    /// `SequenceConfigSheet`/`StateConfigSheet`'s identically-placed toolbar buttons.
    var cancelButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "newProjectSheet.cancelButton").firstMatch
    }
    var createButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "newProjectSheet.createButton").firstMatch
    }
}
