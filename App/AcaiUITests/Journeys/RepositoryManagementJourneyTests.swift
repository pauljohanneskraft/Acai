import XCTest

/// Two codebases cloned from the same remote share one on-disk clone, which `RepositoryDetailView`
/// must refuse to remove while either still references it. Real git against a local fixture remote:
/// only a real clone has a shared hub, a size on disk and worktrees.
@MainActor
final class RepositoryManagementJourneyTests: UIJourneyTestCase {

    func testRepositoryDetailRefusesRemovalWhileACodebaseDependsOnIt() throws {
        var remoteURL = ""
        let browser = launchSeeded { app, destination in
            let remoteDir = destination.appendingPathComponent("GitHubRemote")
            try GitFixtureRepository(directory: remoteDir).makeRemote()
            app.launchEnvironment["ACAI_UITEST_GITHUB_REMOTE_URL"] = remoteDir.path
            remoteURL = URL(fileURLWithPath: remoteDir.path, isDirectory: true).absoluteString
        }
        GitHubAccountScreen(app: app).signInWithToken(through: browser)
        addTwoCodebasesSharingOneClone(browser: browser)

        let repositoryRow = browser.repositoryRow(remoteURL: remoteURL)
        let repository = RepositoryDetailScreen(app: app)
        repositoryRow.tap("the repository's sidebar row", until: repository.fetchNowButton)

        let audit = AccessibilityAudit(testCase: self)
        audit.assertAccessible(repository.fetchNowButton, name: "Fetch Now button")
        audit.assertAccessible(repository.removeButton, name: "Remove button")
        repository.loadedValue(identifier: "repository.diskSizeValue", excluding: "—")
            .waitOrFail("the clone's on-disk size")
        repository.loadedValue(identifier: "repository.lastFetchedValue", excluding: "Never")
            .waitOrFail("the clone's last-fetched time")
        repository.referencingCodebase(named: "fixture-repo").waitOrFail("the first referencing codebase")
        repository.referencingCodebase(named: "fixture-repo-2").waitOrFail("the second referencing codebase")
        repository.refuseRemoval(naming: ["fixture-repo", "fixture-repo-2"])

        returnToSidebar(browser: browser)
        browser.deleteCodebase(browser.sidebarCodebaseRow(named: "fixture-repo-2"))
        repositoryRow.tap("the repository's sidebar row", until: repository.referencingCodebase(named: "fixture-repo"))
        repository.referencingCodebase(named: "fixture-repo-2")
            .waitForDisappearanceOrFail("the deleted codebase in the repository's list")
        repository.refuseRemoval(naming: ["fixture-repo"])
    }

    /// `main` for both on purpose: the point is two codebases sharing one clone, not two branches.
    private func addTwoCodebasesSharingOneClone(browser: ProjectBrowserScreen) {
        let detail = ProjectDetailScreen(app: app)
        browser.projectRow(id: seeded.projectID).tap(
            "the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID)
        )
        for name in ["fixture-repo", "fixture-repo-2"] {
            detail.tapAddCodebase()
            GitHubAccountScreen(app: app).selectGitHubSource()
            let sheet = NewCodebaseSheetScreen(app: app)
            if name != "fixture-repo" {
                sheet.enterName(name)
            }
            sheet.choose("octocat/fixture-repo", from: sheet.repositoryPicker)
            sheet.choose("main", from: sheet.refPicker)
            sheet.cloneButton.waitUntilEnabled("Clone, once a repository and ref are picked")
            sheet.clone()
            detail.codebaseRow(named: name).waitOrFail("the cloned codebase \(name)")
        }
        returnToSidebar(browser: browser)
    }

    private func returnToSidebar(browser: ProjectBrowserScreen) {
        guard SnapshotPlatform().usesCompactLayout else { return }
        browser.backButton.tapWhenReady("the back button to the sidebar")
        browser.projectRow(id: seeded.projectID).waitOrFail("the sidebar")
    }
}
