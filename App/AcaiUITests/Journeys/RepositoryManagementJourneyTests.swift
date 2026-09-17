import XCTest

/// Two codebases cloned from the same remote share one on-disk clone, which `RepositoryDetailView`
/// must refuse to remove while either still references it. Real git against a local fixture remote:
/// removal has to delete an actual clone.
@MainActor
final class RepositoryManagementJourneyTests: UIJourneyTestCase {

    func testRepositoryDetailRefusesRemovalUntilNoCodebaseDependsOnIt() throws {
        var remoteURL = ""
        var fixtureRoot = URL(fileURLWithPath: "/")
        let browser = launchSeeded { app, destination in
            let remoteDir = destination.appendingPathComponent("GitHubRemote")
            try GitFixtureRepository(directory: remoteDir).makeRemote()
            app.launchEnvironment["ACAI_UITEST_GITHUB_REMOTE_URL"] = remoteDir.path
            remoteURL = URL(fileURLWithPath: remoteDir.path, isDirectory: true).absoluteString
            fixtureRoot = destination
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
        repository.codebasesSectionHeader(count: 2).waitOrFail("the two referencing codebases")
        repository.refuseRemoval(naming: "fixture-repo, fixture-repo-2")

        returnToSidebar(browser: browser)
        browser.deleteCodebase(browser.sidebarCodebaseRow(named: "fixture-repo-2"))
        repositoryRow.tap("the repository's sidebar row", until: repository.codebasesSectionHeader(count: 1))
        repository.refuseRemoval(naming: "fixture-repo")

        // On compact width the repository row — this screen's only entry point — goes away with its last
        // referencing codebase, so the removal itself is only reachable on regular width.
        guard !SnapshotPlatform().usesCompactLayout else { return }

        let clones = fixtureRoot.appendingPathComponent("git-repositories")
        XCTAssertFalse(try cloneDirectories(in: clones).isEmpty, "the shared clone should be on disk")
        browser.deleteCodebase(browser.sidebarCodebaseRow(named: "fixture-repo"))
        repository.codebasesSectionHeader(count: 0).waitOrFail("the repository with no referencing codebase")
        repository.remove()
        XCTAssertTrue(try cloneDirectories(in: clones).isEmpty, "removal must delete the shared clone")
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
                sheet.nameField.tapWhenReady("the codebase name field")
                sheet.nameField.typeText(name)
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

    private func cloneDirectories(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
    }
}
