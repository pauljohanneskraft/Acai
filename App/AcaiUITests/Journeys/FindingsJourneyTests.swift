import XCTest

/// The seeded codebase is wired to `Fixtures/seeded/quality.yml`'s always-tripping budget, so it
/// always has a quality violation. One launch covers what that violation reaches: Quick Look over the
/// file it names, and the project-level Findings view with its suppress/unsuppress round trip (a
/// violation has to surface there, not only in `CodebaseDetailView`'s own section).
@MainActor
final class FindingsJourneyTests: UIJourneyTestCase {

    func testAViolationOpensItsSourceAndSurfacesInFindings() throws {
        openIndexedSeededCodebase(analysis: .canned)

        let dismissButton = app.buttons["sourceViewer.dismissButton"]
        app.buttons["violation.viewSourceButton"].firstMatch.tap("View Source", until: dismissButton)
        dismissButton.tapWhenReady("the Quick Look sheet's Done button")
        dismissButton.waitForDisappearanceOrFail("the Quick Look sheet")

        // On iPhone, `ProjectDetailView` and `CodebaseDetailView` share one `NavigationSplitView`
        // detail slot swapped by `Selection`, so the sidebar is one level back from here; regular
        // width keeps the sidebar visible, so there's nothing to pop there.
        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: seeded.projectID)
        if SnapshotPlatform().usesCompactLayout {
            browser.backButton.tap("the navigation back button", until: projectRow)
        }

        let detail = ProjectDetailScreen(app: app)
        projectRow.tap("the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID))
        detail.openFindings()

        let findings = FindingsScreen(app: app)
        findings.list.waitOrFail(
            "the Findings list after reindexing a codebase with an always-tripping budget", timeout: .uiWork
        )
        findings.kindFilter("violation").waitOrFail("the violation kind filter")

        let row = findings.firstViolationRow.waitOrFail("a violation finding row")
        findings.suppressButton(in: row).tapWhenReady("the finding's Suppress button")
        findings.showSuppressedToggle.tapWhenReady("Show suppressed")
        findings.unsuppressButton(in: row).waitOrFail(
            "the suppressed finding under \"show suppressed too\""
        )
    }
}
