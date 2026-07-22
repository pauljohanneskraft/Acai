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
    /// matches by literal label rather than a per-option identifier.
    @discardableResult
    func chooseRef(_ label: String, timeout: TimeInterval = 5) -> XCUIElement {
        refPicker.tap()
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        _ = option.waitForExistence(timeout: timeout)
        option.tap()
        return option
    }
}
