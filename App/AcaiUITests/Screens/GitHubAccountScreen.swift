import XCTest

/// Accessors for `GitHubAccountSection`, embedded in `NewCodebaseSheet`'s "From GitHub" tab — the
/// only place it's reachable today.
@MainActor
final class GitHubAccountScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Matches on label text, not identifier: the segmented "Source" picker's segments surface as a
    /// different element kind on macOS (`NSSegmentedControl`) vs. iOS.
    func selectGitHubSource() {
        app.descendants(matching: .any)["From GitHub"].tap()
    }

    var patField: XCUIElement { app.secureTextFields["github.patField"] }
    var signInWithTokenButton: XCUIElement { app.buttons["github.signInWithTokenButton"] }
    var signInWithDeviceFlowButton: XCUIElement { app.buttons["github.signInWithDeviceFlowButton"] }
    var signedInRow: XCUIElement { app.descendants(matching: .any)["github.signedInRow"] }
    var signOutButton: XCUIElement { app.buttons["github.signOutButton"] }
}
