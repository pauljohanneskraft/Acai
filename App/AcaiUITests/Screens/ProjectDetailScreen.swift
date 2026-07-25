import XCTest

/// Accessors for a project's detail pane (`ProjectDetailView`).
@MainActor
final class ProjectDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// On compact width (iPhone) this action lives behind a "+" toolbar `Menu`;
    /// `openAddMenuIfNeeded` opens it first so this accessor resolves identically either way.
    var addCodebaseButton: XCUIElement {
        openAddMenuIfNeeded(target: "projectDetail.addCodebaseButton")
        return app.buttons["projectDetail.addCodebaseButton"]
    }

    var addDiagramButton: XCUIElement {
        openAddMenuIfNeeded(target: "projectDetail.addDiagramButton")
        return app.buttons["projectDetail.addDiagramButton"]
    }

    /// The compact-width (iPhone) "+" toolbar button; never exists on regular width.
    var addMenuButton: XCUIElement { app.buttons["projectDetail.addMenuButton"] }

    /// A no-op on regular width, or once the menu is already open — checked via `target`'s own
    /// existence first, so repeated calls never tap "+" twice and toggle the menu shut again.
    private func openAddMenuIfNeeded(target: String) {
        guard !app.buttons[target].exists else { return }
        let menuButton = app.buttons["projectDetail.addMenuButton"]
        guard menuButton.exists else { return }
        menuButton.tap()
    }

    /// `.firstMatch`: this identifier can resolve to more than one accessibility node for a
    /// system-styled `.confirmationDialog` action; any one of them performs the same tap.
    var deleteCodebaseConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "projectDetail.codebase.delete.confirmButton").firstMatch
    }

    func codebaseRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["projectDetail.codebaseRow.\(id)"]
    }

    /// A second, discoverable delete path — a destructive button at the bottom of the screen,
    /// alongside the sidebar context-menu path to the same action.
    var deleteProjectButton: XCUIElement { app.buttons["projectDetail.deleteProjectButton"] }
    var deleteProjectConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "projectDetail.project.delete.confirmButton").firstMatch
    }

    /// For a codebase added at test runtime (e.g. cloned from GitHub), whose `id` is a fresh random
    /// UUID the test can't predict ahead of time — matches the row's visible name label instead.
    func codebaseRow(named name: String) -> XCUIElement {
        app.staticTexts[name].firstMatch
    }
}
