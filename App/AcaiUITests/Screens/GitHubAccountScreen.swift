import XCTest

/// Accessors for `GitHubAccountSection` — embedded in `NewCodebaseSheet`'s "From GitHub" tab, the
/// only place it's reachable today (see `TESTING_ARCHITECTURE.md` Layer 2's note on `USABILITY_
/// IMPROVEMENTS.md` Part 4 not having landed a standalone Settings surface yet).
final class GitHubAccountScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// `NewCodebaseSheet`'s segmented "Source" picker has no accessibility identifier of its own
    /// (no existing segmented-control test in this codebase needed one) — its segments surface as
    /// buttons labeled by the source's own display text on iOS, but as a different element kind
    /// under macOS's `NSSegmentedControl`, so this matches on that literal text regardless of
    /// element kind rather than inventing a new identifier scheme for a single call site.
    func selectGitHubSource() {
        app.descendants(matching: .any)["From GitHub"].tap()
    }

    var patField: XCUIElement { app.secureTextFields["github.patField"] }
    var signInWithTokenButton: XCUIElement { app.buttons["github.signInWithTokenButton"] }
    var signInWithDeviceFlowButton: XCUIElement { app.buttons["github.signInWithDeviceFlowButton"] }
    var signedInRow: XCUIElement { app.descendants(matching: .any)["github.signedInRow"] }
    var signOutButton: XCUIElement { app.buttons["github.signOutButton"] }
}
