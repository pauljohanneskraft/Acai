import XCTest
#if os(iOS)
import UIKit
#endif

/// Real `libgit2` clone/fetch mechanics are covered by `GitWorktreeSyncTests`; this journey uses
/// the git-free `FastFixtureGitHubRepositoryService` and only proves the UI/ViewModel wiring.
@MainActor
final class GitHubAddCodebaseTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"

    private static let packageManifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FixtureRepo",
            targets: [
                .target(name: "FixtureRepo")
            ]
        )

        """

    func testAddingSwitchingBranchAndComparingAGitHubCodebaseAllWorkCorrectly() throws {
        let app = XCUIApplication()
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded") { app, destination in
            let remoteRoot = destination.appendingPathComponent("GitHubRemote")
            try GitFixtureRepository(directory: remoteRoot).makeCannedRemote(refs: [
                "main": [
                    "Package.swift": Self.packageManifest,
                    "Sources/FixtureRepo/Widget.swift": "public class Widget {}\n",
                    "Sources/FixtureRepo/Gadget.swift": "public class Gadget {}\n"
                ],
                "feature": [
                    "Package.swift": Self.packageManifest,
                    "Sources/FixtureRepo/Widget.swift": "public class Widget {}\n",
                    "Sources/FixtureRepo/Gadget.swift": "public class Gadget {}\n",
                    "Sources/FixtureRepo/Extra.swift": "public class Extra {}\n"
                ]
            ])
            app.launchArguments += ["-AcaiUITestGitHubFastFixtureRoot", remoteRoot.path]
        }

        let browser = ProjectBrowserScreen(app: app)

        // `GitHubTokenStore` is Keychain-backed and not fixture-redirected — always sign back out
        // via `defer`, even on assertion failure, so this never leaves a stale entry behind.
        let github = GitHubAccountScreen(app: app)
        defer { if github.signedInRow.exists { github.signOutButton.tap() } }
        signIn(app: app, browser: browser, github: github)

        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        XCTAssertTrue(detail.addCodebaseButton.waitForExistence(timeout: 10))
        detail.addCodebaseButton.tap()

        github.selectGitHubSource()
        let sheet = NewCodebaseSheetScreen(app: app)
        XCTAssertTrue(sheet.repositoryPicker.waitForExistence(timeout: 10))
        sheet.choose("octocat/fixture-repo", from: sheet.repositoryPicker)
        XCTAssertTrue(sheet.refPicker.waitForExistence(timeout: 10))
        sheet.choose("main", from: sheet.refPicker)
        XCTAssertTrue(sheet.cloneButton.isEnabled)
        sheet.cloneButton.tap()

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
        XCTAssertFalse(diagram.typeNode(named: "Extra").exists, "feature-only content leaked into main")

        switchBranchAndCompare(app: app, browser: browser, diagram: diagram, codebaseDetail: codebaseDetail)
    }

    /// `backButton` from the diagram pops all the way to the sidebar, not just one level to
    /// `CodebaseDetailScreen`, so re-enter via the sidebar's own codebase row rather than assuming
    /// a fixed stack depth. Only iPhone's compact width covers the sidebar with a push/pop stack in
    /// the first place — macOS and iPad's regular width keep it visible.
    private func switchBranchAndCompare(
        app: XCUIApplication, browser: ProjectBrowserScreen, diagram: ClassDiagramScreen,
        codebaseDetail: CodebaseDetailScreen
    ) {
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

        // Waits on the switch's own completion signal instead of inferring "done" from the diagram
        // button's mere existence, which is already true mid-switch, before content updates.
        XCTAssertTrue(
            codebaseDetail.refSwitchLoadedIndicator.waitForExistence(timeout: UITestWaits.standard.long),
            "the branch switch never finished")
        let classDiagramButtonAfterSwitch = codebaseDetail.diagramButton(type: "class")
        let featureBranchDiagram = ClassDiagramScreen(app: app)
        classDiagramButtonAfterSwitch.tapUntil(featureBranchDiagram.typeNode(named: "Extra"))

        XCTAssertTrue(featureBranchDiagram.typeNode(named: "Extra").waitForExistence(timeout: 10),
                      "switching branches should have picked up feature's new content")

        XCTAssertTrue(featureBranchDiagram.compareButton.waitForExistence(timeout: 10))
        featureBranchDiagram.openCompare()
        featureBranchDiagram.chooseCompareRef("main")
        // `compareLoadingIndicator` distinguishes a genuine still-loading timeout from never
        // reaching a recognizable comparison state at all.
        let loaded = featureBranchDiagram.compareLoadedIndicator.waitForExistence(timeout: UITestWaits.standard.long)
        let errorExists = featureBranchDiagram.compareErrorIndicator.exists
        let errorMessage = errorExists ? featureBranchDiagram.compareErrorIndicator.label : "(no error shown)"
        XCTAssertTrue(loaded, "comparison snapshot never finished loading: \(errorMessage) "
                      + "(still loading: \(featureBranchDiagram.compareLoadingIndicator.exists))")
        XCTAssertFalse(errorExists, errorMessage)
    }

    /// `NewCodebaseSheet`'s GitHub tab reads signed-in state from Settings rather than embedding
    /// its own sign-in UI, so sign in there first.
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
}
