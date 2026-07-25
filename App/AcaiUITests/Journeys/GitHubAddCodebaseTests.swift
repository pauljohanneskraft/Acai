import XCTest
#if os(iOS)
import UIKit
#endif

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
        app.rotateToPortraitOnIPad()
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
        //
        // Both macOS's and iPad's (regular width) `NavigationSplitView` keep the sidebar visible
        // and directly tappable alongside the detail pane at all times — there's no push/pop stack
        // to back out of (no "BackButton" exists on either, confirmed empirically on iPad: it
        // still shows "Hide Sidebar" in the accessibility dump, meaning the sidebar was never
        // covered). Only iPhone's compact width covers the sidebar with a push/pop stack.
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom != .pad {
            diagram.backButton.tap()
        }
        #endif
        let sidebarCodebaseRow = browser.codebaseRow(named: "fixture-repo")
        XCTAssertTrue(sidebarCodebaseRow.waitForExistence(timeout: 10))
        sidebarCodebaseRow.tapUntil(codebaseDetail.refPicker)

        XCTAssertTrue(codebaseDetail.refPicker.waitForExistence(timeout: 10))
        codebaseDetail.chooseRef("feature")

        let classDiagramButtonAfterSwitch = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButtonAfterSwitch.waitForExistence(timeout: 30), "the branch switch never finished")
        // Used for the rest of the test — both re-verifying the switch and then running Compare —
        // so it's named for what it persistently shows (the feature branch), not the one-off event
        // that produced it.
        let featureBranchDiagram = ClassDiagramScreen(app: app)
        classDiagramButtonAfterSwitch.tapUntil(featureBranchDiagram.typeNode(named: "Extra"))

        XCTAssertTrue(featureBranchDiagram.typeNode(named: "Extra").waitForExistence(timeout: 10),
                      "switching branches should have fetched feature's new content into the same clone")

        // Compare — previously impossible for any GitHub-backed codebase (no `.git` directory
        // existed at all) — now works here too, exactly as it does for a local-folder codebase.
        XCTAssertTrue(featureBranchDiagram.compareButton.waitForExistence(timeout: 10))
        featureBranchDiagram.openCompare()
        featureBranchDiagram.chooseCompareRef("main")
        // 30s, not 15s: the "old" side is a real `git` tree extraction + full re-analysis, on top
        // of a GitHub-backed codebase's own clone directory — confirmed empirically that this can
        // occasionally take noticeably longer than a quick structural rebuild, the same class of
        // occasional-slow-update fixed identically in `CompareGitRevisionTests`.
        let loaded = featureBranchDiagram.compareLoadedIndicator.waitForExistence(timeout: 30)
        let errorExists = featureBranchDiagram.compareErrorIndicator.exists
        let errorMessage = errorExists ? featureBranchDiagram.compareErrorIndicator.label : "(no error shown)"
        XCTAssertTrue(loaded, "comparison snapshot never finished loading: \(errorMessage)")
        XCTAssertFalse(errorExists, errorMessage)
    }
}
