import XCTest

/// Verifies GitHub sign-in/out through `GitHubAccountSection`'s personal-access-token path using
/// `FixtureGitHubAccountService`'s canned identity.
///
/// A fixture launch redirects `GitHubTokenStore` to a JSON file under the run's own disposable
/// directory (see its `fixtureFileURL`), so nothing here can reach the real keychain.
@MainActor
final class GitHubSignInTests: UIJourneyTestCase {
    /// Must match `FixtureGitHubAccountService.login` (`Sources/AcaiApp/GitHub/GitHubAccountService.swift`)
    /// — this out-of-process UI test target has no access to `AcaiApp`'s internal symbols.
    private let fixtureLogin = "octocat"

    func testSigningInWithATokenShowsTheAccountRowThenSigningOutRemovesIt() throws {
        let browser = launchSeeded(analysis: .parsed)
        browser.openSettings()

        let github = GitHubAccountScreen(app: app)
        github.patField.tapWhenReady("the personal access token field")
        github.patField.typeText("fixture-token")
        github.signInWithTokenButton.waitUntilEnabled("Sign In with Token, once a token is entered")
        github.signInWithTokenButton.tapWhenReady("Sign In with Token")

        github.signedInRow.waitOrFail("the signed-in account row")
        XCTAssertTrue(app.staticTexts[fixtureLogin].firstMatch.exists)

        github.signOutButton.tapWhenReady("Sign Out")
        github.signedInRow.waitForDisappearanceOrFail("the signed-in account row")
    }
}
