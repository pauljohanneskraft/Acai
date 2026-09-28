import XCTest

/// #179 and #180 against real libgit2 and a local repository staged at launch (`main` with `Widget`
/// and `Gadget`, `feature` adding `Extra`) — no network, and no GitHub account unless the journey is
/// about GitHub.
@MainActor
final class RemoteCodebaseJourneyTests: UIJourneyTestCase {

    /// Any git remote works without signing in to anything: its branches are read before cloning,
    /// and switching branch fetches from it.
    func testCloningARemoteByAddressWorksWithoutAnAccount() throws {
        var remoteDirectory: URL?
        let browser = launchSeeded(analysis: .parsed) { _, destination in
            let directory = destination.appendingPathComponent("TeamRemote")
            try GitFixtureRepository(directory: directory).makeRemote()
            remoteDirectory = directory
        }
        let remotePath = try XCTUnwrap(remoteDirectory).path

        let detail = ProjectDetailScreen(app: app)
        browser.projectRow(id: seeded.projectID).tap(
            "the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID)
        )
        detail.tapAddCodebase()

        let sheet = NewCodebaseSheetScreen(app: app)
        sheet.selectRemoteURLSource()
        sheet.enterRemoteAddress(remotePath)
        sheet.cloneButton.waitUntilEnabled("Clone, once the remote's branches are read")
        sheet.clone()

        let codebaseRow = detail.codebaseRow(named: "TeamRemote")
        codebaseRow.waitOrFail("the cloned codebase's row")
        let codebaseDetail = CodebaseDetailScreen(app: app)
        codebaseRow.tap("the cloned codebase's row", until: codebaseDetail.refPicker)
        // `switchRef` waits for the operation to report loaded, which now means it actually succeeded.
        // That the switched worktree holds the branch's own content is
        // `ProjectCodebaseEditorRemoteSyncTests.switchingRefMovesTheWorktreeAndRecordsTheNewRef`,
        // so this no longer builds a diagram to read `Extra` off the canvas.
        codebaseDetail.switchRef(to: "feature")
    }

    /// A repository GitHub reports as large asks before cloning; the latest-snapshot clone says so,
    /// and the hotspot chart asks for the full history instead of charting one commit.
    func testALargeRepositoryCanBeClonedAsItsLatestSnapshotAndDeepenedLater() throws {
        let browser = launchSeeded(analysis: .parsed) { app, destination in
            let remoteDir = destination.appendingPathComponent("GitHubRemote")
            try GitFixtureRepository(directory: remoteDir).makeRemote()
            app.launchEnvironment["ACAI_UITEST_GITHUB_REMOTE_URL"] = remoteDir.path
            app.launchEnvironment["ACAI_UITEST_GITHUB_REPOSITORY_SIZE_KB"] = "900000"
        }

        let github = GitHubAccountScreen(app: app)
        github.signInWithToken(through: browser)

        let detail = ProjectDetailScreen(app: app)
        browser.projectRow(id: seeded.projectID).tap(
            "the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID)
        )
        detail.tapAddCodebase()

        github.selectGitHubSource()
        let sheet = NewCodebaseSheetScreen(app: app)
        sheet.choose("octocat/fixture-repo", from: sheet.repositoryPicker)
        sheet.choose("main", from: sheet.refPicker)
        sheet.cloneButton.waitUntilEnabled("Clone, once a repository and ref are picked")
        sheet.answerLargeCloneWarning(with: sheet.cloneLatestSnapshotButton)

        let codebaseRow = detail.codebaseRow(named: "fixture-repo")
        codebaseRow.waitOrFail("the cloned codebase's row")
        let codebaseDetail = CodebaseDetailScreen(app: app)
        codebaseRow.tap("the cloned codebase's row", until: codebaseDetail.latestSnapshotBadge)
        // Deepened from the badge rather than through the hotspot screen: that a shallow clone reports
        // "history not fetched" instead of charting one commit is
        // `HotspotViewModelTests.aShallowCloneSaysHistoryIsNotFetchedInsteadOfChartingOneCommit`.
        codebaseDetail.fetchFullHistory()
    }
}
