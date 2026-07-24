import CoreGraphics
import XCTest

/// The Layer 2 screenshot journey (`TESTING_ARCHITECTURE.md`): drives the seeded-project journey
/// and, at each named milestone, both attaches a screenshot for human review and diffs it via
/// `ScreenshotComparator` — this is the real screen-level visual regression mechanism, since
/// Layer 1's `ImageRenderer`-based harness structurally can't render full interactive screens.
final class ScreenshotJourneyTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private var comparator: ScreenshotComparator {
        ScreenshotComparator(goldenDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__"))
    }

    func testSeededJourneyScreenshots() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        // Waiting on the codebase row itself, not `addCodebaseButton`, reaches this screen
        // identically on both compact (iPhone) and regular width — see `AccessibilityAuditTests`'
        // comment on why `addCodebaseButton` isn't reachable the same way on both.
        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        comparator.validate(
            viewType: "ProjectDetail", state: "populated", screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )

        // The compact-width (iPhone) "+" toolbar button only ever opens this Menu — it doesn't
        // navigate anywhere by itself, so this is what pressing it actually shows. Regular width
        // (iPad/macOS) has no such button (`addCodebaseButton`/`addDiagramButton` sit directly in
        // the toolbar/header there instead), so this state doesn't exist to capture on those
        // platforms.
        if detail.addMenuButton.exists {
            detail.addMenuButton.tap()
            comparator.validate(
                viewType: "ProjectDetail", state: "addMenuOpen",
                screenshot: app.windows.firstMatch.screenshot(), testCase: self
            )
        }

        // `tapUntil`, not a plain `.tap()`: when the menu above was opened, the first tap here only
        // dismisses it (standard tap-outside-a-menu behavior) rather than also registering on
        // `codebaseRow` underneath — retrying until the next screen actually appears handles both
        // that case and the plain "menu was never opened" case identically.
        let codebaseDetail = CodebaseDetailScreen(app: app)
        codebaseRow.tapUntil(codebaseDetail.reindexButton)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10))
        codebaseDetail.reindexButton.tap()

        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 30))
        let diagram = ClassDiagramScreen(app: app)
        classDiagramButton.tapUntil(diagram.typeNode(named: "Base"))

        XCTAssertTrue(diagram.typeNode(named: "Base").waitForExistence(timeout: 10))
        comparator.validate(
            viewType: "ClassDiagram", state: "populated", screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )

        // Double-tapping a node selects it and switches the sidebar to the Inspector tab in one
        // action (`ClassDiagramView`'s `.onTapGesture(count: 2)`). `.firstMatch`: unlike `.tap()`,
        // `.doubleTap()` requires resolving to a single element, but every row of text inside
        // `TypeNodeView` carries the same identifier (observed empirically via the accessibility
        // tree dump on iOS).
        diagram.typeNode(named: "Base").firstMatch.doubleTap()
        XCTAssertTrue(diagram.inspectorContent.waitForExistence(timeout: 10))
        comparator.validate(
            viewType: "ClassDiagram", state: "inspectorOpen",
            screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )
    }
}
