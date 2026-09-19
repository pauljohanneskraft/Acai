import XCTest

final class ClassDiagramScreen: DiagramScreenBase {
    /// Keyed by `TypeDeclaration.name` — `TypeNodeView` has no separate stable id of its own.
    func typeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.typeNode.\(name)"]
    }

    /// A type node as VoiceOver reads it: labelled with its name and carrying a non-empty description.
    func describedTypeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label == %@ AND value != nil AND value != ''",
            "diagram.typeNode.\(name)", name
        )).firstMatch
    }

    /// Matched by its spoken label, which names both ends in whatever language the app runs in.
    func relationship(from source: String, to target: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'diagram.edge.' AND label CONTAINS %@ AND label CONTAINS %@ AND value != ''",
            source, target
        )).firstMatch
    }

    // MARK: - Focus (Settings tab)

    var focusToggle: XCUIElement { app.descendants(matching: .any)["diagram.focus.toggle"].firstMatch }
    var focusRootTypePicker: XCUIElement { app.descendants(matching: .any)["diagram.focus.rootTypePicker"] }

    /// Focuses on the first type name alphabetically, following its dependencies.
    func enableFocus(file: StaticString = #filePath, line: UInt = #line) {
        revealInSettings(focusToggle, "the Focus toggle", file: file, line: line)
        // On iOS the identified element is the whole row; a tap at its centre lands on the label and
        // doesn't flip it, so tap the nested switch instead.
        #if os(macOS)
        let control = focusToggle
        #else
        let control = focusToggle.switches.firstMatch
        #endif
        control.tapWhenReady("the Focus toggle", file: file, line: line)
        focusRootTypePicker.waitOrFail("the focus root type picker", file: file, line: line)
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
