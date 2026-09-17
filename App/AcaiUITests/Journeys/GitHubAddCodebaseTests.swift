import XCTest
#if os(iOS)
import UIKit
#endif

/// Adding a GitHub-backed codebase does a real `libgit2` clone, and switching its branch does a
/// real incremental fetch into the *same* clone directory — verified behaviorally by asserting the
/// Class Diagram's node set actually changes after the switch, plus that Compare works.
///
/// Stays on real git deliberately: `FastFixtureGitHubRepositoryService` is git-free (a plain
/// directory copy, no `.git` at all), but Compare's `GitDiffSnapshot.extractedDirectory()` needs an
/// actual git repository to extract a historical ref from — it isn't a candidate for that fixture.
///
/// No real network access: `FixtureGitHubRepositoryService` clones/fetches from a local repository
/// `GitFixtureRepository` builds fresh at launch — `main` with two commits (`Widget`, `Gadget`),
/// `feature` one commit further ahead (`Extra`) — instead of github.com.
@MainActor
final class GitHubAddCodebaseTests: UIJourneyTestCase {

    func testAddingSwitchingBranchAndComparingAGitHubCodebaseAllWorkAgainstARealLocalClone() throws {
        let browser = launchSeeded(analysis: .parsed) { app, destination in
            let remoteDir = destination.appendingPathComponent("GitHubRemote")
            try GitFixtureRepository(directory: remoteDir).makeRemote()
            app.launchEnvironment["ACAI_UITEST_GITHUB_REMOTE_URL"] = remoteDir.path
        }

        let github = GitHubAccountScreen(app: app)
        signIn(browser: browser, github: github)

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
        sheet.clone()

        let codebaseRow = detail.codebaseRow(named: "fixture-repo")
        codebaseRow.waitOrFail("the cloned codebase's row")
        let codebaseDetail = CodebaseDetailScreen(app: app)
        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        codebaseRow.tap("the cloned codebase's row", until: classDiagramButton)

        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
        diagram.typeNode(named: "Widget").waitOrFail("the Widget type node", timeout: .uiWork)
        XCTAssertTrue(diagram.typeNode(named: "Gadget").exists)
        XCTAssertFalse(diagram.typeNode(named: "Extra").exists, "feature-only content leaked into the main clone")

        switchBranchAndCompare(browser: browser, diagram: diagram, codebaseDetail: codebaseDetail)
    }

    /// `backButton` from the diagram pops all the way to the sidebar, not just one level to
    /// `CodebaseDetailScreen`, so re-enter via the sidebar's own codebase row rather than assuming
    /// a fixed stack depth. Only iPhone's compact width covers the sidebar with a push/pop stack in
    /// the first place — macOS and iPad's regular width keep it visible.
    private func switchBranchAndCompare(
        browser: ProjectBrowserScreen, diagram: ClassDiagramScreen, codebaseDetail: CodebaseDetailScreen
    ) {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom != .pad {
            diagram.backButton.tapWhenReady("the diagram's back button")
        }
        #endif
        browser.codebaseRow(named: "fixture-repo").tap(
            "the cloned codebase's sidebar row", until: codebaseDetail.refPicker
        )
        codebaseDetail.switchRef(to: "feature")

        let featureBranchDiagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
        featureBranchDiagram.typeNode(named: "Extra").waitOrFail(
            "the Extra type node (switching branches should have fetched feature's content into the same clone)",
            timeout: .uiWork
        )

        featureBranchDiagram.openCompare()
        featureBranchDiagram.compare(against: "main")
    }

    /// `NewCodebaseSheet`'s GitHub tab reads signed-in state from Settings rather than embedding
    /// its own sign-in UI, so sign in there first. A fixture launch redirects `GitHubTokenStore`
    /// into this run's disposable directory, so no sign-out is needed afterwards.
    private func signIn(browser: ProjectBrowserScreen, github: GitHubAccountScreen) {
        browser.openSettings()
        github.patField.tapWhenReady("the personal access token field")
        github.patField.typeText("fixture-token")
        github.signInWithTokenButton.tapWhenReady("Sign In with Token")
        github.signedInRow.waitOrFail("the signed-in account row")
        browser.closeSettings()
    }
}
