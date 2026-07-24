import XCTest

/// Accessors for `NewCodebaseSheet`'s GitHub tab — the repository/branch pickers and the Clone
/// action. Kept separate from `GitHubAccountScreen` (embedded inside this same sheet), which stays
/// scoped to the sign-in section it wraps. See `TESTING_ARCHITECTURE.md` Layer 2.
final class NewCodebaseSheetScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var repositoryPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.repositoryPicker"] }
    var refPicker: XCUIElement { app.descendants(matching: .any)["newCodebase.refPicker"] }
    var cloneButton: XCUIElement { app.buttons["newCodebase.cloneButton"] }

    /// Picks a repository/ref from their respective `Picker`s. A SwiftUI `Picker` in a `Form`
    /// surfaces differently per platform (a popup-button menu on macOS, a pushed list or inline
    /// menu on iOS) and the option itself has no separate identifier, so this matches by its
    /// literal text across every plausible element kind — acceptable here since the fixture's
    /// repository/ref names are fixed and known ahead of time. Matches on `label` **or** `title`:
    /// confirmed by dumping the accessibility tree that a macOS popup button's `NSMenuItem`
    /// exposes its text via the `title` attribute with `label` left empty (the opposite of most
    /// other control types here, which populate `label`) — a plain `label == %@` predicate matched
    /// nothing on macOS even though the item was genuinely present the whole time. Returns the
    /// matched option element (already waited-for) so the caller can assert its existence before
    /// tapping.
    @discardableResult
    func choose(_ label: String, from picker: XCUIElement, timeout: TimeInterval = 10) -> XCUIElement {
        picker.tap()
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@", label, label)).firstMatch
        _ = option.waitForExistence(timeout: timeout)
        option.tap()
        return option
    }
}
