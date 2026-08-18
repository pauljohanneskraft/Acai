import XCTest

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

    // MARK: - Signed-in detail

    var usedByCodebasesLabel: XCUIElement { app.descendants(matching: .any)["github.usedByCodebasesLabel"] }
    var expiryWarning: XCUIElement { app.descendants(matching: .any)["github.expiryWarning"] }
    var refreshScopesButton: XCUIElement { app.buttons["github.refreshScopesButton"] }

    // MARK: - Scope checklist

    var scopeChecklist: XCUIElement { app.descendants(matching: .any)["github.scopeChecklist"] }
    var scopesUnknownLabel: XCUIElement { app.descendants(matching: .any)["github.scopesUnknownLabel"] }

    // MARK: - `NewCodebaseSheet`'s read-only summary (points at Settings instead of embedding sign-in)

    var newCodebaseSignedInAsLabel: XCUIElement {
        app.descendants(matching: .any)["newCodebase.signedInAsLabel"]
    }
    var newCodebaseOpenSettingsButton: XCUIElement { app.buttons["newCodebase.openSettingsButton"] }
}
