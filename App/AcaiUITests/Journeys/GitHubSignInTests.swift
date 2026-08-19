import XCTest

/// Verifies GitHub sign-in/out through `GitHubAccountSection`'s personal-access-token path using
/// `FixtureGitHubAccountService`'s canned identity.
///
/// A fixture launch redirects `GitHubTokenStore` to a JSON file under the run's own disposable
/// directory (see its `fixtureFileURL`), so nothing here can reach the real keychain and the
/// `defer` below is belt-and-braces rather than the isolation mechanism. It also would not run on
/// an assertion failure — XCTest aborts the test with an Objective-C exception, which does not
/// unwind Swift `defer`.
@MainActor
final class GitHubSignInTests: UIJourneyTestCase {
    /// Must match `FixtureGitHubAccountService.login` (`Sources/AcaiApp/GitHub/GitHubAccountService.swift`)
    /// — this UI test target is a separate, out-of-process Xcode-project target with no access to
    /// `AcaiApp`'s internal symbols, unlike `Tests/AcaiAppTests`'s `@testable import`, so the two
    /// can't share a constant.
    private static let fixtureLogin = "octocat"

    func testSigningInWithATokenShowsTheAccountRowThenSigningOutRemovesIt() throws {
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
        XCTAssertTrue(github.signedInRow.waitForNonExistence(timeout: 5))
    }
}
