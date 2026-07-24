import XCTest

/// Accessors for a codebase's detail pane (`CodebaseDetailView`) — the reindex action and the
/// per-`DiagramType` generation buttons. See `TESTING_ARCHITECTURE.md` Layer 2.
final class CodebaseDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var reindexButton: XCUIElement { app.buttons["codebaseDetail.reindexButton"] }

    /// `type` is a `DiagramType.rawValue` (e.g. `"class"`, `"sequence"`, `"callGraph"`).
    func diagramButton(type: String) -> XCUIElement {
        app.buttons["codebaseDetail.diagramButton.\(type)"]
    }

    /// Branch/tag picker + Pull button, shown instead of `reindexButton` for a GitHub-backed
    /// codebase — see `CodebaseDetailView.githubActions`.
    var refPicker: XCUIElement { app.descendants(matching: .any)["codebaseDetail.refPicker"] }
    var pullButton: XCUIElement { app.buttons["codebaseDetail.pullButton"] }

    /// Picks a branch/tag from `refPicker` — see `NewCodebaseSheetScreen.choose` for why this
    /// matches by literal label/title rather than a per-option identifier (including why both
    /// `label` and `title` are checked: a macOS popup button's `NSMenuItem` only populates `title`).
    @discardableResult
    func chooseRef(_ label: String, timeout: TimeInterval = 10) -> XCUIElement {
        refPicker.tap()
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@", label, label)).firstMatch
        _ = option.waitForExistence(timeout: timeout)
        option.tap()
        return option
    }

    /// B53's second, discoverable delete path — a destructive button at the bottom of the screen,
    /// alongside the existing sidebar/row context-menu path to the same confirmed-safe action.
    var deleteCodebaseButton: XCUIElement { app.buttons["codebaseDetail.deleteCodebaseButton"] }
    var deleteCodebaseConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "codebaseDetail.codebase.delete.confirmButton").firstMatch
    }
}
