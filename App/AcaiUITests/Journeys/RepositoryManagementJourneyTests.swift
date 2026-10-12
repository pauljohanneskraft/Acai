import XCTest

/// Codebases cloned from the same remote share one on-disk clone. Real git against a local fixture
/// remote: only a real clone has a shared hub, a size on disk and worktrees.
///
/// Everything around that clone is staged rather than driven, so the journey spends its allowance on
/// git: the GitHub account comes from the fixture (`GitHubSignInTests` owns the sign-in form) and
/// each clone's first index reads the canned artifact instead of parsing the cloned package.
@MainActor
final class RepositoryManagementJourneyTests: UIJourneyTestCase {

    func testRepositoryDetailShowsTheSharedCloneAndTheCodebasesUsingIt() throws {
        var remoteURL = ""
        let browser = launchSeeded(analysis: .cannedForEveryCodebase) { app, destination in
            try SeededFixture().stageSignedInGitHubAccount(in: destination)
            remoteURL = try Self.stageRemote(for: app, in: destination)
        }
        // `main` for both on purpose: the point is two codebases sharing one clone, not two branches.
        addCodebases([("fixture-repo", "main"), ("fixture-repo-2", "main")], browser: browser)

        let repositoryRow = browser.repositoryRow(remoteURL: remoteURL)
        let repository = RepositoryDetailScreen(app: app)
        repositoryRow.tap("the repository's sidebar row", until: repository.fetchNowButton)

        let audit = AccessibilityAudit(testCase: self)
        audit.assertAccessible(repository.fetchNowButton, name: "Fetch Now button")
        repository.loadedValue(identifier: "repository.diskSizeValue", excluding: "—")
            .waitOrFail("the clone's on-disk size")
        repository.loadedValue(identifier: "repository.lastFetchedValue", excluding: "Never")
            .waitOrFail("the clone's last-fetched time")
        repository.referencingCodebase(named: "fixture-repo").waitOrFail("the first referencing codebase")
        repository.referencingCodebase(named: "fixture-repo-2").waitOrFail("the second referencing codebase")

        // The sidebar row's own Delete affordance and its confirmation, which no other journey
        // reaches. That the repository's list then drops the codebase is
        // `RepositoryDetailModelTests.referencingCodebasesFollowTheStoreAfterRemoval`.
        returnToSidebar(browser: browser)
        browser.deleteCodebase(browser.sidebarCodebaseRow(named: "fixture-repo-2"))
    }

    private static func stageRemote(for app: XCUIApplication, in destination: URL) throws -> String {
        let remoteDir = destination.appendingPathComponent("GitHubRemote")
        try GitFixtureRepository(directory: remoteDir).makeRemote()
        app.launchEnvironment["ACAI_UITEST_GITHUB_REMOTE_URL"] = remoteDir.path
        return URL(fileURLWithPath: remoteDir.path, isDirectory: true).absoluteString
    }

    private func addCodebases(_ codebases: [(name: String, ref: String)], browser: ProjectBrowserScreen) {
        let detail = ProjectDetailScreen(app: app)
        browser.projectRow(id: seeded.projectID).tap(
            "the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID)
        )
        for codebase in codebases {
            detail.addFixtureGitHubCodebase(named: codebase.name, ref: codebase.ref)
        }
        returnToSidebar(browser: browser)
    }

    private func returnToSidebar(browser: ProjectBrowserScreen) {
        guard SnapshotPlatform().usesCompactLayout else { return }
        browser.backButton.tapWhenReady("the back button to the sidebar")
        browser.projectRow(id: seeded.projectID).waitOrFail("the sidebar")
    }
}
