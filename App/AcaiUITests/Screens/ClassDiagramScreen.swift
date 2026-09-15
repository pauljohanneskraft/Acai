import XCTest

final class ClassDiagramScreen: DiagramScreenBase {
    /// Keyed by `TypeDeclaration.name` — `TypeNodeView` has no separate stable id of its own.
    func typeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.typeNode.\(name)"]
    }

    // MARK: - Find in Diagram

    var searchToggleButton: XCUIElement { app.buttons["diagram.search.toggleButton"] }
    var searchField: XCUIElement { app.textFields["diagram.search.field"] }
    var searchMatchSummary: XCUIElement { app.staticTexts["diagram.search.matchSummary"] }
    var searchNextButton: XCUIElement { app.buttons["diagram.search.nextButton"] }
    var searchPreviousButton: XCUIElement { app.buttons["diagram.search.previousButton"] }
    var searchDismissButton: XCUIElement { app.buttons["diagram.search.dismissButton"] }

    func openSearch(file: StaticString = #filePath, line: UInt = #line) {
        tapToolbarButton(searchToggleButton, label: "Find in Diagram", file: file, line: line)
        searchField.waitOrFail("the diagram search field", file: file, line: line)
    }
}
