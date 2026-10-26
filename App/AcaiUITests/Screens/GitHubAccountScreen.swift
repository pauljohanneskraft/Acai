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
    /// `.firstMatch`: a `.confirmationDialog` action can surface as more than one accessibility node.
    var signOutConfirmButton: XCUIElement { app.buttons["github.signOut.confirmButton"].firstMatch }
    var signOutCancelButton: XCUIElement { app.buttons["github.signOut.cancelButton"].firstMatch }

    /// Taps Sign Out, leaving its confirmation on screen for the caller to answer.
    func openSignOutConfirmation(file: StaticString = #filePath, line: UInt = #line) {
        signOutButton.tapWhenReady("Sign Out", file: file, line: line)
        signOutConfirmButton.waitOrFail("the sign-out confirmation", file: file, line: line)
    }

    /// iOS presents the dialog as a popover without its Cancel button; tapping outside cancels it.
    func cancelSignOut(file: StaticString = #filePath, line: UInt = #line) {
        #if os(iOS)
        // Inside the Settings sheet but off the dialog: a tap outside the sheet dismisses it too on iPad.
        let scopeChecklist = app.descendants(matching: .any)["github.scopeChecklist"].firstMatch
        scopeChecklist.waitOrFail("the scope checklist beside the sign-out confirmation", file: file, line: line)
        SystemBanners().dismiss(file: file, line: line)
        scopeChecklist.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        #else
        signOutCancelButton.tapWhenReady("Cancel, in the sign-out confirmation", file: file, line: line)
        #endif
        signOutConfirmButton.waitForDisappearanceOrFail("the sign-out confirmation", file: file, line: line)
        signedInRow.waitOrFail("the signed-in account row after cancelling", file: file, line: line)
    }

    #if os(iOS)
    /// An iOS `Form` turns a row into a tap target for its default-style button; this row must not ask to sign out.
    func tapAccountRowBesideSignOut(file: StaticString = #filePath, line: UInt = #line) {
        // A wrongly triggered dialog appeared well within this locally; a slow runner can only miss it, never fail.
        let presentationWindow: TimeInterval = 3
        let checklist = scopeChecklist.firstMatch
        checklist.waitOrFail("the scope checklist in the account row", file: file, line: line)
        SystemBanners().dismiss(file: file, line: line)
        checklist.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if signOutConfirmButton.waitForExistence(timeout: presentationWindow) {
            XCTFail("Tapping the account row beside Sign Out asked to sign out", file: file, line: line)
        }
    }
    #endif

    func confirmSignOut(file: StaticString = #filePath, line: UInt = #line) {
        signOutConfirmButton.tapWhenReady("Sign Out, in the confirmation", file: file, line: line)
        signedInRow.waitForDisappearanceOrFail("the signed-in account row", file: file, line: line)
    }

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
