import CoreGraphics
import XCTest

/// Drives the seeded-project journey and, at each named milestone, both attaches a screenshot for
/// human review and diffs it via `ScreenshotComparator` — this is the real screen-level visual
/// regression mechanism, since `ImageRenderer`-based rendering structurally can't render full
/// interactive screens.
@MainActor
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
        app.rotateToLandscapeOnIPad()
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
            viewType: "ProjectDetail", state: "populated",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )

        // The compact-width (iPhone) "+" toolbar button only ever opens this Menu — it doesn't
        // navigate anywhere by itself. Regular width (iPad/macOS) has no such button
        // (`addCodebaseButton`/`addDiagramButton` sit directly in the toolbar/header there
        // instead), so this state doesn't exist to capture on those platforms.
        if detail.addMenuButton.exists {
            detail.addMenuButton.tap()
            // Looser than the file's shared default (measured, not guessed): a `Menu`'s
            // presentation on iOS renders through a translucent material, and two recordings of
            // this exact state — confirmed fresh installs each time, `screenshotAfterAnimationsIdle`
            // confirming the rest of the frame had stopped changing — still differed by ~0.35% in
            // the blurred region behind the menu. `ProjectDetail/iPhone/populated.png` (same screen,
            // same run, no menu open) was pixel-identical across the same passes, so the source
            // isn't this screen's layout, it's the `Menu` material not converging to the same bytes
            // twice — the same class of noise the macOS default already accounts for, just smaller.
            comparator.validate(
                viewType: "ProjectDetail", state: "addMenuOpen",
                screenshot: app.screenshotAfterAnimationsIdle(), testCase: self, maxChangedFraction: 7.0e-3
            )
            // The open menu is covered by a full-screen (invisible outside its own bounds) touch
            // blocker — confirmed via a debug screenshot showing the row visually unobstructed yet
            // still reported "not hittable" — so any single coordinate tap dismisses it; bottom
            // center is safely below both the menu and all real row content.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        }

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
            viewType: "ClassDiagram", state: "populated",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
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
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )
    }
}
