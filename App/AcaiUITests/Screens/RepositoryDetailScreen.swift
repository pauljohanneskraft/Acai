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

    /// Only once details have loaded and show a real value — macOS exposes a static text's content as
    /// `value`, iOS as `label`.
    func loadedValue(identifier: String, excluding placeholder: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND NOT (label == %@ OR value == %@)", identifier, placeholder, placeholder
        )).firstMatch
    }

    /// An entry in the screen's list of codebases referencing the repository.
    func referencingCodebase(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["repository.codebase.\(name)"]
    }

    /// Removal must be refused while a codebase still references the repository, with a message
    /// naming each one that does.
    func refuseRemoval(naming names: [String], file: StaticString = #filePath, line: UInt = #line) {
        removeButton.tapWhenReady("the Remove button", file: file, line: line)
        let message = NSCompoundPredicate(andPredicateWithSubpredicates: (["reassign"] + names).map {
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@ OR title CONTAINS %@", $0, $0, $0)
        })
        app.staticTexts.matching(message).firstMatch
            .waitOrFail("the removal-refused message naming \(names.joined(separator: ", "))", file: file, line: line)
        removalBlockedOKButton.tapWhenReady("the removal-refused alert's OK button", file: file, line: line)
        removalBlockedOKButton.waitForDisappearanceOrFail("the removal-refused alert", file: file, line: line)
    }
}
