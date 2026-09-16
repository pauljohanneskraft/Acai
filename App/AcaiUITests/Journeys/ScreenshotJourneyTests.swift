import XCTest

/// Drives the seeded-project journey and, at each named milestone, validates a screenshot — the
/// screen-level visual regression mechanism, since `ImageRenderer`-based rendering structurally
/// can't render full interactive screens.
///
/// The accessibility audit rides along on the same walk rather than in its own test: it asserts on
/// exactly the screens this already visits, so a separate journey only bought a second cold launch
/// of the identical path.
@MainActor
final class ScreenshotJourneyTests: UIJourneyTestCase {
    private var audit: AccessibilityAudit { AccessibilityAudit(testCase: self) }

    func testSeededJourneyScreenshots() throws {
        let browser = launchSeeded(analysis: .canned)
        let projectRow = browser.projectRow(id: seeded.projectID)
        projectRow.waitOrFail("the seeded project's sidebar row")
        audit.assertAccessible(browser.newProjectButton, name: "New Project button")

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: seeded.codebaseID)
        projectRow.tap("the seeded project's sidebar row", until: codebaseRow)
        validateScreenshot("ProjectDetail", state: "populated")

        let codebaseDetail = CodebaseDetailScreen(app: app)
        codebaseRow.tap("the seeded codebase's row", until: codebaseDetail.reindexButton)
        audit.assertAccessible(codebaseDetail.reindexButton, name: "Reindex button")
        codebaseDetail.reindex()

        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
        diagram.typeNode(named: "Base").waitOrFail("the Base type node", timeout: .uiWork)
        audit.assertAccessible(diagram.undoButton, name: "Undo button")
        audit.assertAccessible(diagram.redoButton, name: "Redo button")
        validateScreenshot("ClassDiagram", state: "populated")

        // `.firstMatch`: unlike `.tap()`, `.doubleTap()` requires resolving to a single element,
        // but every row of text inside `TypeNodeView` carries the same identifier.
        let base = diagram.typeNode(named: "Base").firstMatch
        base.waitUntilReady("the Base type node")
        base.doubleTap()
        diagram.inspectorContent.waitOrFail("the Inspector for Base")
        validateScreenshot("ClassDiagram", state: "inspectorOpen")
    }

    func testProjectDetailAddMenuScreenshot() throws {
        try XCTSkipUnless(SnapshotPlatform().usesCompactLayout, "only compact width hides these actions behind \"+\"")
        let detail = openSeededProject()
        detail.openAddMenu()
        // iOS's `Menu` renders through a translucent material that doesn't converge to identical bytes
        // between recordings of the same state.
        validateScreenshot("ProjectDetail", state: "addMenuOpen", maxChangedFraction: 7.0e-3)
    }
}
