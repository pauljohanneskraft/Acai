import XCTest

/// Proves the headline change of the real-git-engine slice end to end, through the real app UI:
/// adding a GitHub-backed codebase now does a real `libgit2` clone (not a zipball download), and
/// switching its branch does a real incremental fetch into the *same* clone directory (not a full
/// re-download) — verified behaviorally by asserting the Class Diagram's node set actually changes
/// after the switch, plus that Compare (previously impossible for any GitHub-backed codebase) works.
///
/// No real network access: `FixtureGitHubRepositoryService` (`Sources/AcaiApp/GitHub/
/// GitHubRepositoryService.swift`) clones/fetches from a local repository `GitFixtureRepository`
/// builds fresh at launch — `main` with two commits (`Widget`, `Gadget`), `feature` one commit
/// further ahead (`Extra`) — instead of github.com. Sign-in still goes through
/// `FixtureGitHubAccountService`'s canned PAT path (`GitHubSignInTests`), since the credential
/// value itself is never actually used to reach a real server on this path.
final class GitHubAddCodebaseTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"

    func testAddingSwitchingBranchAndComparingAGitHubCodebaseAllWorkAgainstARealLocalClone() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded") { app, destination in
            let remoteDir = destination.appendingPathComponent("GitHubRemote")
            try GitFixtureRepository(directory: remoteDir).makeRemote()
            app.launchArguments += ["-AcaiUITestGitHubRemoteURL", remoteDir.path]
        }

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        XCTAssertTrue(detail.addCodebaseButton.waitForExistence(timeout: 10))
        detail.addCodebaseButton.tap()

        let github = GitHubAccountScreen(app: app)
        github.selectGitHubSource()
        // The real Keychain-backed `GitHubTokenStore` isn't fixture-redirected — always sign back
        // out via `defer`, even if an assertion above it fails, so this never leaves a stale entry
        // for the next run. See `GitHubSignInTests`' identical comment.
        defer { if github.signedInRow.exists { github.signOutButton.tap() } }

        XCTAssertTrue(github.patField.waitForExistence(timeout: 5))
        github.patField.tap()
        github.patField.typeText("fixture-token")
        github.signInWithTokenButton.tap()
        XCTAssertTrue(github.signedInRow.waitForExistence(timeout: 5))

        let sheet = NewCodebaseSheetScreen(app: app)
        XCTAssertTrue(sheet.repositoryPicker.waitForExistence(timeout: 10))
        sheet.choose("octocat/fixture-repo", from: sheet.repositoryPicker)
        XCTAssertTrue(sheet.refPicker.waitForExistence(timeout: 10))
        sheet.choose("main", from: sheet.refPicker)
        XCTAssertTrue(sheet.cloneButton.isEnabled)
        sheet.cloneButton.tap()

        // The sheet dismisses once cloning + the initial reindex both finish.
        let codebaseRow = detail.codebaseRow(named: "fixture-repo")
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 30), "the GitHub clone/index never finished")
        let codebaseDetail = CodebaseDetailScreen(app: app)
        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        codebaseRow.tapUntil(classDiagramButton)

        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 10))
        let diagram = ClassDiagramScreen(app: app)
        classDiagramButton.tapUntil(diagram.typeNode(named: "Widget"))

        XCTAssertTrue(diagram.typeNode(named: "Widget").waitForExistence(timeout: 10))
        XCTAssertTrue(diagram.typeNode(named: "Gadget").exists)
        XCTAssertFalse(diagram.typeNode(named: "Extra").exists, "feature-only content leaked into the main clone")

        // Back to the codebase detail screen to switch branches: a real incremental fetch +
        // checkout into the *same* clone directory — not a fresh full re-download — so the
        // diagram's node set should now include `Extra`. `backButton` from the diagram pops all
        // the way to the sidebar (not just one level to `CodebaseDetailScreen`), so re-enter via
        // the sidebar's own codebase row rather than assuming a fixed stack depth.
        diagram.backButton.tap()
        let sidebarCodebaseRow = browser.codebaseRow(named: "fixture-repo")
        XCTAssertTrue(sidebarCodebaseRow.waitForExistence(timeout: 10))
        sidebarCodebaseRow.tapUntil(codebaseDetail.refPicker)

        XCTAssertTrue(codebaseDetail.refPicker.waitForExistence(timeout: 10))
        codebaseDetail.chooseRef("feature")

        let classDiagramButtonAfterSwitch = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButtonAfterSwitch.waitForExistence(timeout: 30), "the branch switch never finished")
        let diagramAfterSwitch = ClassDiagramScreen(app: app)
        classDiagramButtonAfterSwitch.tapUntil(diagramAfterSwitch.typeNode(named: "Extra"))

        XCTAssertTrue(diagramAfterSwitch.typeNode(named: "Extra").waitForExistence(timeout: 10),
                      "switching branches should have fetched feature's new content into the same clone")

        // Compare — previously impossible for any GitHub-backed codebase (no `.git` directory
        // existed at all) — now works here too, exactly as it does for a local-folder codebase.
        XCTAssertTrue(diagramAfterSwitch.compareToggle.waitForExistence(timeout: 10))
        diagramAfterSwitch.tapCompareToggle()
        diagramAfterSwitch.compareRefField.clearAndTypeText("main\n")
        let loaded = diagramAfterSwitch.compareLoadedIndicator.waitForExistence(timeout: 15)
        let errorExists = diagramAfterSwitch.compareErrorIndicator.exists
        let errorMessage = errorExists ? diagramAfterSwitch.compareErrorIndicator.label : "(no error shown)"
        XCTAssertTrue(loaded, "comparison snapshot never finished loading: \(errorMessage)")
        XCTAssertFalse(errorExists, errorMessage)
    }
}
