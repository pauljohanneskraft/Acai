import XCTest

@MainActor
final class RepositoryDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var fetchNowButton: XCUIElement { app.buttons["repository.fetchNowButton"] }
    var removeButton: XCUIElement { app.buttons["repository.removeButton"] }
    var removalBlockedOKButton: XCUIElement {
        app.buttons.matching(identifier: "repository.removalBlocked.okButton").firstMatch
    }

    /// `.firstMatch`: this identifier can resolve to more than one accessibility node for a
    /// system-styled `.confirmationDialog` action, matching `ProjectDetailScreen`'s equivalent.
    var removeConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "repository.remove.confirmButton").firstMatch
    }

    /// Only once details have loaded and show a real value — macOS exposes a static text's content as
    /// `value`, iOS as `label`.
    func loadedValue(identifier: String, excluding placeholder: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND NOT (label == %@ OR value == %@)", identifier, placeholder, placeholder
        )).firstMatch
    }

    func codebasesSectionHeader(count: Int) -> XCUIElement {
        app.staticTexts["Codebases (\(count))"]
    }

    /// Removal must be refused while a codebase still references the repository, with a message
    /// naming what does.
    func refuseRemoval(naming names: String, file: StaticString = #filePath, line: UInt = #line) {
        removeButton.tapWhenReady("the Remove button", file: file, line: line)
        app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "reassign \(names) first", "reassign \(names) first"
        )).firstMatch.waitOrFail("the removal-refused message naming \(names)", file: file, line: line)
        removalBlockedOKButton.tapWhenReady("the removal-refused alert's OK button", file: file, line: line)
        removalBlockedOKButton.waitForDisappearanceOrFail("the removal-refused alert", file: file, line: line)
    }

    func remove(file: StaticString = #filePath, line: UInt = #line) {
        removeButton.tapWhenReady("the Remove button", file: file, line: line)
        removeConfirmButton.tapWhenReady("the removal confirmation", file: file, line: line)
        fetchNowButton.waitForDisappearanceOrFail("the removed repository's detail screen", file: file, line: line)
    }
}
