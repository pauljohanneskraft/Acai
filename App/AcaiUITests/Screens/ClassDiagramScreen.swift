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

    /// The match summary once it reads `text`, matched in the query so a wait re-evaluates it. macOS
    /// exposes this text through `value` with `label` empty; iOS through `label`.
    func searchMatchSummary(reading text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "identifier == 'diagram.search.matchSummary' AND (label == %@ OR value == %@)", text, text
        )).firstMatch
    }
    var searchNextButton: XCUIElement { app.buttons["diagram.search.nextButton"] }
    var searchPreviousButton: XCUIElement { app.buttons["diagram.search.previousButton"] }
    var searchDismissButton: XCUIElement { app.buttons["diagram.search.dismissButton"] }

    func openSearch(file: StaticString = #filePath, line: UInt = #line) {
        tapToolbarButton(
            identifier: "diagram.search.toggleButton", label: "Find in Diagram", until: searchField,
            file: file, line: line
        )
        searchField.waitOrFail("the diagram search field", file: file, line: line)
    }
}
