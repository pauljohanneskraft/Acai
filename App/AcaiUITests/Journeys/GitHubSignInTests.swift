import XCTest

/// Verifies GitHub sign-in/out through `GitHubAccountSection`'s personal-access-token path (no
/// device-flow polling to simulate — deterministic by construction) using
/// `FixtureGitHubAccountService`'s canned identity, proving the seam described in
/// `TESTING_ARCHITECTURE.md` Layer 2 actually works end to end, not just that it compiles.
///
/// `GitHubTokenStore` is Keychain-backed and not fixture-redirected, so a successful stubbed
/// sign-in still writes to the real keychain item under `de.kraftsoftware.Acai.github` — this test
/// always signs back out via `defer`, even if an assertion above it fails, so it never leaves a
/// stale entry for the next run on a reused simulator/host.
final class GitHubSignInTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    /// Must match `FixtureGitHubAccountService.login` (`Sources/AcaiApp/GitHub/GitHubAccountService.swift`)
    /// — this UI test target is a separate, out-of-process Xcode-project target with no access to
    /// `AcaiApp`'s internal symbols, unlike `Tests/AcaiAppTests`'s `@testable import`, so the two
    /// can't share a constant.
    private static let fixtureLogin = "octocat"

    func testSigningInWithATokenShowsTheAccountRowThenSigningOutRemovesIt() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        XCTAssertTrue(detail.addCodebaseButton.waitForExistence(timeout: 10))
        detail.addCodebaseButton.tap()

        let github = GitHubAccountScreen(app: app)
        github.selectGitHubSource()
        defer { if github.signedInRow.exists { github.signOutButton.tap() } }

        XCTAssertTrue(github.patField.waitForExistence(timeout: 5))
        github.patField.tap()
        github.patField.typeText("fixture-token")
        XCTAssertTrue(github.signInWithTokenButton.isEnabled)
        github.signInWithTokenButton.tap()

        XCTAssertTrue(github.signedInRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Signed in as \(Self.fixtureLogin)"].exists)

        github.signOutButton.tap()
        XCTAssertFalse(github.signedInRow.waitForExistence(timeout: 5))
    }
}
