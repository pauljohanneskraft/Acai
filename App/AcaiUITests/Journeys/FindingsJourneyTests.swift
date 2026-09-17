import XCTest

/// Reindexing the seeded fixture's codebase (wired to `Fixtures/seeded/quality.yml`'s
/// always-tripping budget, exactly like `ViewSourceQuickLookTests`) produces a quality violation
/// that should surface in the project-level Findings view, not just `CodebaseDetailView`'s own
/// section. Also exercises the suppress/unsuppress round trip.
@MainActor
final class FindingsJourneyTests: UIJourneyTestCase {

    func testFindingsViewSurfacesViolationAfterReindex() throws {
        openIndexedSeededCodebase(analysis: .canned)

        // On iPhone, `ProjectDetailView` and `CodebaseDetailView` share one `NavigationSplitView`
        // detail slot swapped by `Selection`, so the sidebar is one level back from here; regular
        // width keeps the sidebar visible, so there's nothing to pop there.
        let projectRow = ProjectBrowserScreen(app: app).projectRow(id: seeded.projectID)
        if SnapshotPlatform().usesCompactLayout {
            app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap("the navigation back button", until: projectRow)
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
