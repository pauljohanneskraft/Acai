import XCTest

@MainActor
final class RepositoryDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var fetchNowButton: XCUIElement { app.buttons["repository.fetchNowButton"] }

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
}
