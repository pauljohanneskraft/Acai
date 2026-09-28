import XCTest

/// Codebases cloned from the same remote share one on-disk clone. Real git against a local fixture
/// remote: only a real clone has a shared hub, a size on disk and worktrees.
@MainActor
final class RepositoryManagementJourneyTests: UIJourneyTestCase {

    func testRepositoryDetailShowsTheSharedCloneAndTheCodebasesUsingIt() throws {
        var remoteURL = ""
        let browser = launchSeeded { app, destination in
            remoteURL = try Self.stageRemote(for: app, in: destination)
        }
        GitHubAccountScreen(app: app).signInWithToken(through: browser)
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

        returnToSidebar(browser: browser)
        browser.deleteCodebase(browser.sidebarCodebaseRow(named: "fixture-repo-2"))
        repositoryRow.tap("the repository's sidebar row", until: repository.referencingCodebase(named: "fixture-repo"))
        repository.referencingCodebase(named: "fixture-repo-2")
            .waitForDisappearanceOrFail("the deleted codebase in the repository's list")
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

    private func openClassDiagram(of codebase: String, browser: ProjectBrowserScreen) -> ClassDiagramScreen {
        let codebaseDetail = CodebaseDetailScreen(app: app)
        browser.sidebarCodebaseRow(named: codebase).tap(
            "\(codebase)'s sidebar row", until: codebaseDetail.diagramButton(type: "class")
        )
        return codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
    }

    /// Pulls from the codebase screen, then opens a fresh class diagram of what the pull left on disk.
    private func pullAndReopen(_ codebase: String, browser: ProjectBrowserScreen) -> ClassDiagramScreen {
        let codebaseDetail = CodebaseDetailScreen(app: app)
        browser.sidebarCodebaseRow(named: codebase).tap("\(codebase)'s sidebar row", until: codebaseDetail.pullButton)
        codebaseDetail.pullButton.tapWhenReady("Pull")
        codebaseDetail.pullOperation.waitUntilLoaded("Pulling \(codebase)")
        XCTAssertFalse(app.alerts.firstMatch.exists, "pulling \(codebase) reported an error")
        return codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
    }

    /// On compact width the diagram's back button pops all the way to the sidebar; regular width
    /// keeps the sidebar on screen.
    private func leaveDiagram(_ diagram: ClassDiagramScreen) {
        guard SnapshotPlatform().usesCompactLayout else { return }
        diagram.backButton.tapWhenReady("the diagram's back button")
    }

    private func returnToSidebar(browser: ProjectBrowserScreen) {
        guard SnapshotPlatform().usesCompactLayout else { return }
        browser.backButton.tapWhenReady("the back button to the sidebar")
        browser.projectRow(id: seeded.projectID).waitOrFail("the sidebar")
    }

    /// The app deletes worktrees and clones in the background, so this polls the fixture's own
    /// storage rather than reading it once.
    private func waitForEntries(
        in directory: URL, count: Int, _ description: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let path = directory.path
        let predicate = NSPredicate { _, _ in
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            return entries.filter { !$0.hasPrefix(".") }.count == count
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        guard XCTWaiter().wait(for: [expectation], timeout: .uiWork) == .completed else {
            let found = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            XCTFail("\(description): expected \(count) entries in \(directory.lastPathComponent), found \(found)",
                    file: file, line: line)
            return
        }
    }
}
