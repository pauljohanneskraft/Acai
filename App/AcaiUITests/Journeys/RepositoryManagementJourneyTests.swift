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

    /// Two codebases at different revisions of one repository live side by side on a single clone;
    /// deleting one leaves the other working, and deleting the last one deletes the clone.
    func testCodebasesAtDifferentRevisionsShareOneClone() throws {
        var remoteURL = ""
        var baseDir = URL(fileURLWithPath: "/")
        let browser = launchSeeded(analysis: .parsed) { app, destination in
            remoteURL = try Self.stageRemote(for: app, in: destination)
            baseDir = destination
        }
        let clones = baseDir.appendingPathComponent("git-repositories", isDirectory: true)
        let worktrees = baseDir.appendingPathComponent("git-worktrees", isDirectory: true)
        GitHubAccountScreen(app: app).signInWithToken(through: browser)
        addCodebases([("fixture-main", "main"), ("fixture-feature", "feature")], browser: browser)

        waitForEntries(in: clones, count: 1, "a single shared clone for both codebases")
        waitForEntries(in: worktrees, count: 2, "one worktree per codebase")
        let repositoryRow = browser.repositoryRow(remoteURL: remoteURL)
        let repository = RepositoryDetailScreen(app: app)
        repositoryRow.tap("the repository's sidebar row", until: repository.referencingCodebase(named: "fixture-main"))
        repository.referencingCodebase(named: "fixture-feature").waitOrFail("the second referencing codebase")
        returnToSidebar(browser: browser)

        let mainDiagram = openClassDiagram(of: "fixture-main", browser: browser)
        mainDiagram.typeNode(named: "Widget").waitOrFail("main's Widget type node", timeout: .uiWork)
        XCTAssertTrue(mainDiagram.typeNode(named: "Gadget").exists)
        XCTAssertFalse(mainDiagram.typeNode(named: "Extra").exists, "feature's content leaked into main's worktree")
        leaveDiagram(mainDiagram)
        let featureDiagram = openClassDiagram(of: "fixture-feature", browser: browser)
        featureDiagram.typeNode(named: "Extra").waitOrFail("feature's Extra type node", timeout: .uiWork)
        leaveDiagram(featureDiagram)

        browser.deleteCodebase(browser.sidebarCodebaseRow(named: "fixture-main"))
        waitForEntries(in: worktrees, count: 1, "the remaining codebase's worktree")
        waitForEntries(in: clones, count: 1, "the shared clone kept for the remaining codebase")
        let pulledDiagram = pullAndReopen("fixture-feature", browser: browser)
        pulledDiagram.typeNode(named: "Extra").waitOrFail("feature's Extra type node after pulling", timeout: .uiWork)
        leaveDiagram(pulledDiagram)

        browser.deleteCodebase(browser.sidebarCodebaseRow(named: "fixture-feature"))
        waitForEntries(in: clones, count: 0, "the clone deleted along with its last codebase")
        repositoryRow.waitForDisappearanceOrFail("the repository's sidebar row once no codebase uses it")
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
