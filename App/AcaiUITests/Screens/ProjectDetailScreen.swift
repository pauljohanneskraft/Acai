import XCTest

@MainActor
final class ProjectDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var addCodebaseButton: XCUIElement { app.buttons["projectDetail.addCodebaseButton"] }
    var addDiagramButton: XCUIElement { app.buttons["projectDetail.addDiagramButton"] }
    var findingsButton: XCUIElement { app.buttons["projectDetail.findingsButton"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["projectDetail.emptyState"] }

    /// The compact-width (iPhone) "+" toolbar button; never exists on regular width.
    var addMenuButton: XCUIElement { app.buttons["projectDetail.addMenuButton"] }

    func tapAddCodebase(file: StaticString = #filePath, line: UInt = #line) {
        tapAddMenuItem(addCodebaseButton, description: "Add Codebase", file: file, line: line)
    }

    /// Clones the fixture GitHub repository at `ref` into a new codebase and waits for its row.
    /// `name` defaults to the sheet's own suggestion, the repository's name.
    func addFixtureGitHubCodebase(
        named name: String = "fixture-repo", ref: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        tapAddCodebase(file: file, line: line)
        GitHubAccountScreen(app: app).selectGitHubSource(file: file, line: line)
        let sheet = NewCodebaseSheetScreen(app: app)
        if name != "fixture-repo" {
            sheet.enterName(name, file: file, line: line)
        }
        sheet.choose("octocat/fixture-repo", from: sheet.repositoryPicker, file: file, line: line)
        sheet.choose(ref, from: sheet.refPicker, file: file, line: line)
        sheet.cloneButton.waitUntilEnabled("Clone, once a repository and ref are picked", file: file, line: line)
        sheet.clone(file: file, line: line)
        codebaseRow(named: name).waitOrFail("the cloned codebase \(name)", file: file, line: line)
    }

    func tapAddDiagram(file: StaticString = #filePath, line: UInt = #line) {
        tapAddMenuItem(addDiagramButton, description: "Add Diagram", file: file, line: line)
    }

    func openFindings(file: StaticString = #filePath, line: UInt = #line) {
        tapAddMenuItem(findingsButton, description: "Findings", file: file, line: line)
    }

    /// Regular width shows these actions directly; compact width hides them behind "+".
    private func tapAddMenuItem(_ item: XCUIElement, description: String, file: StaticString, line: UInt) {
        if SnapshotPlatform().usesCompactLayout {
            addMenuButton.tap("the \"+\" menu", until: item, file: file, line: line)
        }
        item.tapWhenReady(description, file: file, line: line)
    }

    /// Only meaningful on compact width. Opening a `Menu` has no side effect, so this may retry.
    /// There is deliberately no counterpart to close it: the open menu's items sit over the "+"
    /// button and the screen edge is the home indicator's, so no tap reliably dismisses it — a
    /// journey that opens it ends there.
    func openAddMenu(file: StaticString = #filePath, line: UInt = #line) {
        addMenuButton.tap("the \"+\" menu", until: addCodebaseButton, file: file, line: line)
    }

    /// `.firstMatch`: this identifier can resolve to more than one accessibility node for a
    /// system-styled `.confirmationDialog` action; any one of them performs the same tap.
    var deleteCodebaseConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "projectDetail.codebase.delete.confirmButton").firstMatch
    }

    func codebaseRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["projectDetail.codebaseRow.\(id)"]
    }

    /// Per-row in-flight state: present in place of the checkmark/dashed-circle while a
    /// reindex/fetch/clone concerning this codebase is running — see `CodebaseIndexStatusBadge`.
    func codebaseIndexingSpinner(id: String) -> XCUIElement {
        app.descendants(matching: .any)["codebaseRow.indexingSpinner.\(id)"]
    }

    func freeformDiagramRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["projectDetail.freeformDiagramRow.\(id)"]
    }

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
