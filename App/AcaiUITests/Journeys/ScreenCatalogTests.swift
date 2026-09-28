import XCTest

/// Screens that had no golden at all, captured in one launch: the project browser and an indexed
/// codebase in English (only their German counterparts were covered), the project-level Findings list
/// and a freeform diagram.
///
/// Every state here is reached by opening something and waiting for it — no gestures, no retries, no
/// reindexing — so the run is the same length and shape every time. The launch is pre-indexed, which
/// is what makes an indexed codebase capturable at all: its "Last indexed" date is fixed rather than
/// being whenever the reindex happened to finish.
@MainActor
final class ScreenCatalogTests: UIJourneyTestCase {
    private let freeformDiagramID = "33333333-3333-3333-3333-333333333333"

    func testTheCatalogOfScreensThatHadNoGolden() throws {
        let browser = launchSeeded(analysis: .preindexed)
        browser.newProjectButton.waitOrFail("the project browser")
        validateScreenshot("ProjectBrowser", state: "populated")

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: seeded.codebaseID)
        browser.projectRow(id: seeded.projectID).tap("the seeded project's sidebar row", until: codebaseRow)

        let codebaseDetail = CodebaseDetailScreen(app: app)
        codebaseRow.tap("the seeded codebase's row", until: codebaseDetail.queryButton)
        validateScreenshot("CodebaseDetail", state: "indexed")

        // Findings lives on the project screen, so the detail slot has to hold it again: compact
        // width pops the codebase off first, regular width just re-selects the project.
        let projectRow = browser.projectRow(id: seeded.projectID)
        if SnapshotPlatform().usesCompactLayout {
            browser.backButton.tap("the navigation back button", until: projectRow)
        }
        projectRow.tap("the seeded project's sidebar row", until: codebaseRow)
        detail.openFindings()
        let findings = FindingsScreen(app: app)
        findings.list.waitOrFail("the project's Findings list", timeout: .uiWork)
        validateScreenshot("Findings", state: "populated")

        browser.openLink("acai://diagram/\(freeformDiagramID)")
        let freeform = FreeformDiagramScreen(app: app)
        freeform.openedIndicator.waitOrFail("the seeded freeform diagram")
        validateScreenshot("FreeformDiagram", state: "populated")
    }
}
