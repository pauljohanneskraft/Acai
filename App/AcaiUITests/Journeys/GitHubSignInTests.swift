import XCTest

/// Verifies GitHub sign-in/out through `GitHubAccountSection`'s personal-access-token path using
/// `FixtureGitHubAccountService`'s canned identity.
///
/// `GitHubTokenStore` is Keychain-backed and not fixture-redirected, so a successful stubbed
/// sign-in still writes to the real keychain item under `de.kraftsoftware.Acai.github` — this test
/// always signs back out via `defer`, even if an assertion above it fails, so it never leaves a
/// stale entry for the next run on a reused simulator/host.
@MainActor
final class GitHubSignInTests: XCTestCase {
    /// Must match `FixtureGitHubAccountService.login` (`Sources/AcaiApp/GitHub/GitHubAccountService.swift`)
    /// — this UI test target is a separate, out-of-process Xcode-project target with no access to
    /// `AcaiApp`'s internal symbols, unlike `Tests/AcaiAppTests`'s `@testable import`, so the two
    /// can't share a constant.
    private static let fixtureLogin = "octocat"

    func testSigningInWithATokenShowsTheAccountRowThenSigningOutRemovesIt() throws {
        let app = XCUIApplication()
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        #if os(macOS)
        // macOS reaches Settings via the real `Settings` scene, not a sidebar button — ⌘, opens it.
        app.typeKey(",", modifierFlags: .command)
        #else
        XCTAssertTrue(browser.settingsButton.waitForExistence(timeout: 10))
        browser.settingsButton.tap()
        #endif

        let github = GitHubAccountScreen(app: app)
        defer { if github.signedInRow.exists { github.signOutButton.tap() } }

        XCTAssertTrue(github.patField.waitForExistence(timeout: 5))
        github.patField.tap()
        github.patField.typeText("fixture-token")
        XCTAssertTrue(github.signInWithTokenButton.isEnabled)
        github.signInWithTokenButton.tap()

        XCTAssertTrue(github.signedInRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[Self.fixtureLogin].firstMatch.exists)

        github.signOutButton.tap()
        XCTAssertFalse(github.signedInRow.waitForExistence(timeout: 5))
    }
}
