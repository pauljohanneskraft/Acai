import XCTest

/// Accessors for a project's detail pane (`ProjectDetailView`). See `TESTING_ARCHITECTURE.md`
/// Layer 2.
final class ProjectDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// On regular width this is a directly-tappable toolbar button; on compact width (iPhone) the
    /// same action lives behind a "+" toolbar `Menu` instead (`ProjectDetailView`'s
    /// `#if !os(macOS)` toolbar) — `openAddMenuIfNeeded` opens it first so this accessor resolves
    /// identically either way.
    var addCodebaseButton: XCUIElement {
        openAddMenuIfNeeded(target: "projectDetail.addCodebaseButton")
        return app.buttons["projectDetail.addCodebaseButton"]
    }

    var addDiagramButton: XCUIElement {
        openAddMenuIfNeeded(target: "projectDetail.addDiagramButton")
        return app.buttons["projectDetail.addDiagramButton"]
    }

    /// A no-op on regular width (where `addMenuButton` never exists) or once the menu is already
    /// open (checked via `target`'s own existence first, so repeated property access — e.g. a
    /// `waitForExistence` followed later by a `.tap()` — never taps the "+" button twice, which
    /// would toggle the menu shut again instead of leaving it open).
    private func openAddMenuIfNeeded(target: String) {
        guard !app.buttons[target].exists else { return }
        let menuButton = app.buttons["projectDetail.addMenuButton"]
        guard menuButton.exists else { return }
        menuButton.tap()
    }

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

    /// B53's second, discoverable delete path — a destructive button at the bottom of the screen,
    /// alongside the existing sidebar context-menu path to the same confirmed-safe action.
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
