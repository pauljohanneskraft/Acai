import XCTest
#if os(iOS)
import UIKit
#endif

/// The Repositories sidebar section and `RepositoryDetailView` — on-disk size, last fetched,
/// worktrees, and removing a shared clone — had no automated coverage at all before this. Two
/// codebases cloned from the same GitHub remote share one on-disk clone (the shared-clone design
/// this screen exists to manage), which lets this journey drive the refusal case: removal must stay
/// blocked while either codebase still references the repository, and only proceed once neither does.
///
/// No real network access — see `GitHubAddCodebaseTests`'s equivalent doc comment: `main` with two
/// commits, cloned from a local repository `GitFixtureRepository` builds fresh at launch.
@MainActor
final class RepositoryManagementJourneyTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"

    func testRepositoryDetailRefusesRemovalUntilNoCodebaseDependsOnIt() throws {
        let browser = ProjectBrowserScreen(app: app)
        let github = GitHubAccountScreen(app: app)
        defer { if github.signedInRow.exists { github.signOutButton.tap() } }
        let remoteURL = launchWithTwoCodebasesSharingOneRepository(browser: browser, github: github)

        let repositoryRow = browser.repositoryRow(remoteURL: remoteURL)
        let repositoryDetail = RepositoryDetailScreen(app: app)
        XCTAssertTrue(repositoryRow.waitForExistence(timeout: 10))
        repositoryRow.tapUntil(repositoryDetail.fetchNowButton)
        assertScreenShowsRepositoryDetails(repositoryDetail, expectedCodebaseCount: 2)

        assertRemovalIsBlocked(repositoryDetail, mentioning: "fixture-repo")
        deleteSidebarCodebase(named: "fixture-repo-2", browser: browser)
        reselectRepositoryRow(repositoryRow, repositoryDetail: repositoryDetail)
        XCTAssertTrue(repositoryDetail.codebasesSectionHeader(count: 1).waitForExistence(timeout: 5))

        assertRemovalIsBlocked(repositoryDetail, mentioning: "fixture-repo")

        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            // Compact width (iPhone) only ever reaches `RepositoryDetailView` through the sidebar's
            // repository row, which — by design (`RepositoryIndexEntry`/`ProjectBrowserView
            // +Repositories.swift`) — disappears the instant its last referencing codebase is gone.
            // Deleting that last codebase requires leaving this screen (the sidebar row itself has no
            // delete affordance), so there is no path back to confirm the actual removal on iPhone.
            // Everything through the second refusal above is still fully exercised there; the
            // successful-removal round trip below is regular-width-only (macOS, iPad).
            return
        }
        #endif

        assertSuccessfulRemoval(repositoryRow: repositoryRow, repositoryDetail: repositoryDetail, browser: browser)
    }

    /// Returns the repository's expected `sidebar.repository.<remoteURL>` accessibility identifier
    /// suffix. `FixtureGitHubRepositoryService` reports the *local* fixture remote it actually clones
    /// from as `RepositoryIndexEntry.remoteURL` (see `GitHubRepositoryService.swift`'s
    /// `attachWorktree`), not a `https://github.com/...` URL — the same `URL(fileURLWithPath:
    /// isDirectory:)` construction `UITestFixtureResolver.resolveGitHubRemoteURL()` uses, so this must
    /// match that exactly rather than a plausible-looking GitHub URL literal.
    private func launchWithTwoCodebasesSharingOneRepository(
        browser: ProjectBrowserScreen, github: GitHubAccountScreen
    ) -> String {
        app.rotateToPortraitOnIPad()
        var remoteURL = ""
        app.launchWithFixture("seeded") { app, destination in
            let remoteDir = destination.appendingPathComponent("GitHubRemote")
            try GitFixtureRepository(directory: remoteDir).makeRemote()
            app.launchEnvironment["ACAI_UITEST_GITHUB_REMOTE_URL"] = remoteDir.path
            remoteURL = URL(fileURLWithPath: remoteDir.path, isDirectory: true).absoluteString
        }
        signIn(app: app, browser: browser, github: github)

        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let sheet = NewCodebaseSheetScreen(app: app)
        addGitHubCodebase(detail: detail, github: github, sheet: sheet, name: nil)
        XCTAssertTrue(
            detail.codebaseRow(named: "fixture-repo").waitForExistence(timeout: 30),
            "the GitHub clone/index never finished")
        addGitHubCodebase(detail: detail, github: github, sheet: sheet, name: "fixture-repo-2")
        XCTAssertTrue(
            detail.codebaseRow(named: "fixture-repo-2").waitForExistence(timeout: 30),
            "the second, shared-clone codebase never finished")
        return remoteURL
    }

    private func assertScreenShowsRepositoryDetails(
        _ repositoryDetail: RepositoryDetailScreen, expectedCodebaseCount: Int
    ) {
        let audit = AccessibilityAudit(testCase: self)
        audit.assertAccessible(repositoryDetail.fetchNowButton, name: "Fetch Now button")
        audit.assertAccessible(repositoryDetail.removeButton, name: "Remove button")

        XCTAssertTrue(repositoryDetail.diskSizeValue.waitForExistence(timeout: 10))
        XCTAssertNotEqual(
            repositoryDetail.diskSizeValue.label, "—",
            "a freshly cloned repository must report a real on-disk size")
        XCTAssertTrue(repositoryDetail.lastFetchedValue.waitForExistence(timeout: 5))
        XCTAssertNotEqual(
            repositoryDetail.lastFetchedValue.label, "Never",
            "a freshly cloned repository must have a last-fetched time")
        XCTAssertTrue(
            repositoryDetail.codebasesSectionHeader(count: expectedCodebaseCount).waitForExistence(timeout: 5))
    }

    private func assertRemovalIsBlocked(_ repositoryDetail: RepositoryDetailScreen, mentioning name: String) {
        XCTAssertTrue(repositoryDetail.removeButton.waitForExistence(timeout: 5))
        repositoryDetail.removeButton.tap()
        XCTAssertTrue(
            repositoryDetail.blockedAlertOKButton.waitForExistence(timeout: 5),
            "removal must be refused while a codebase still depends on the repository")
        let message = repositoryDetail.blockedAlert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", name, name)
        ).firstMatch
        XCTAssertTrue(message.exists, "the blocked alert should name what still references the repository")
        repositoryDetail.blockedAlertOKButton.tap()
    }

    private func assertSuccessfulRemoval(
        repositoryRow: XCUIElement, repositoryDetail: RepositoryDetailScreen, browser: ProjectBrowserScreen
    ) {
        deleteSidebarCodebase(named: "fixture-repo", browser: browser)
        XCTAssertTrue(repositoryDetail.codebasesSectionHeader(count: 0).waitForExistence(timeout: 5))

        XCTAssertTrue(repositoryDetail.removeButton.waitForExistence(timeout: 5))
        repositoryDetail.removeButton.tap()
        XCTAssertTrue(
            repositoryDetail.removeConfirmButton.waitForExistence(timeout: 5),
            "removal must be allowed once no codebase references the repository")
        repositoryDetail.removeConfirmButton.tap()

        XCTAssertTrue(
            repositoryRow.waitForNonExistence(timeout: 10),
            "the repository must disappear from the sidebar once removed")
    }

    /// `main` for both, on purpose: the point is two codebases sharing one on-disk clone, not two
    /// branches — `GitHubAddCodebaseTests` already covers switching branches on a single codebase.
    private func addGitHubCodebase(
        detail: ProjectDetailScreen, github: GitHubAccountScreen, sheet: NewCodebaseSheetScreen, name: String?
    ) {
        XCTAssertTrue(detail.addCodebaseButton.waitForExistence(timeout: 10))
        detail.addCodebaseButton.tap()
        github.selectGitHubSource()

        if let name {
            XCTAssertTrue(sheet.nameField.waitForExistence(timeout: 10))
            sheet.nameField.tap()
            sheet.nameField.typeText(name)
        }
        XCTAssertTrue(sheet.repositoryPicker.waitForExistence(timeout: 10))
        sheet.choose("octocat/fixture-repo", from: sheet.repositoryPicker)
        XCTAssertTrue(sheet.refPicker.waitForExistence(timeout: 10))
        sheet.choose("main", from: sheet.refPicker)
        XCTAssertTrue(sheet.cloneButton.waitForExistence(timeout: 10))
        sheet.cloneButton.tap()
    }

    /// `NewCodebaseSheet`'s GitHub tab reads signed-in state from Settings rather than embedding its
    /// own sign-in UI, so sign in there first — mirrors `GitHubAddCodebaseTests.signIn`.
    private func signIn(app: XCUIApplication, browser: ProjectBrowserScreen, github: GitHubAccountScreen) {
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        XCTAssertTrue(browser.settingsButton.waitForExistence(timeout: 10))
        browser.settingsButton.tap()
        #endif
        XCTAssertTrue(github.patField.waitForExistence(timeout: 5))
        github.patField.tap()
        github.patField.typeText("fixture-token")
        github.signInWithTokenButton.tap()
        XCTAssertTrue(github.signedInRow.waitForExistence(timeout: 5))
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        let settings = SettingsScreen(app: app)
        settings.doneButton.tap()
        #endif
    }

    /// Deletes a codebase through the sidebar row's own delete affordance (context menu on
    /// macOS/iPad, swipe on iPhone) — matches `DeleteConfirmationTests.tapDelete`, retargeted at the
    /// sidebar's `sidebar.codebase.delete.confirmButton` rather than `ProjectDetailView`'s own.
    private func deleteSidebarCodebase(named name: String, browser: ProjectBrowserScreen) {
        // On compact width the sidebar is off-screen while `RepositoryDetailView` is pushed; pop back
        // to it first (regular width keeps the sidebar visible throughout, so there's nothing to pop).
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 5) {
            backButton.tap()
        }

        let row = browser.codebaseRow(named: name)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        #if os(macOS)
        row.rightClick()
        app.windows.firstMatch.descendants(matching: .any)["Delete"].tap()
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            row.press(forDuration: 1.0)
        } else {
            row.swipeLeft()
        }
        app.buttons["Delete"].tap()
        #endif
        XCTAssertTrue(browser.deleteCodebaseConfirmButton.waitForExistence(timeout: 5))
        browser.deleteCodebaseConfirmButton.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "confirming the deletion must remove the codebase")
    }

    /// Re-establishes `.repository` selection after `deleteSidebarCodebase` may have popped away from
    /// it (compact width) — a harmless re-tap where it never left (regular width).
    private func reselectRepositoryRow(_ row: XCUIElement, repositoryDetail: RepositoryDetailScreen) {
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tapUntil(repositoryDetail.fetchNowButton)
    }
}
