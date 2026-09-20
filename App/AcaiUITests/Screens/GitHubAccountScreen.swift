import XCTest

@MainActor
final class GitHubAccountScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    func selectGitHubSource(file: StaticString = #filePath, line: UInt = #line) {
        let repositoryPicker = NewCodebaseSheetScreen(app: app).repositoryPicker
        NewCodebaseSheetScreen(app: app).sourceSegment("gitHub", label: "GitHub").tap(
            "the GitHub source", until: repositoryPicker, file: file, line: line
        )
    }

    var patField: XCUIElement { app.secureTextFields["github.patField"] }
    var signInWithTokenButton: XCUIElement { app.buttons["github.signInWithTokenButton"] }
    var signInWithDeviceFlowButton: XCUIElement { app.buttons["github.signInWithDeviceFlowButton"] }
    var signedInRow: XCUIElement { app.descendants(matching: .any)["github.signedInRow"] }
    var signOutButton: XCUIElement { app.buttons["github.signOutButton"] }

    /// `NewCodebaseSheet`'s GitHub tab reads signed-in state from Settings rather than embedding its
    /// own sign-in UI. A fixture launch redirects `GitHubTokenStore` into the run's disposable
    /// directory, so no sign-out is needed afterwards.
    func signInWithToken(through browser: ProjectBrowserScreen, file: StaticString = #filePath, line: UInt = #line) {
        browser.openSettings(file: file, line: line)
        patField.tapWhenReady("the personal access token field", file: file, line: line)
        patField.typeText("fixture-token")
        signInWithTokenButton.tapWhenReady("Sign In with Token", file: file, line: line)
        signedInRow.waitOrFail("the signed-in account row", file: file, line: line)
        browser.closeSettings(file: file, line: line)
    }

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
