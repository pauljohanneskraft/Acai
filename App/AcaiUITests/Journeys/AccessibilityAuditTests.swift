import XCTest

/// Walks the seeded-project journey's own screens and asserts every interactive element it
/// touches has a real accessibility label, not just an identifier.
///
/// Tap-target misses below Apple HIG's 44×44pt minimum are logged, not asserted — flip
/// `logIfBelowMinimumTapTarget` to a hard `XCTAssertGreaterThanOrEqual` once the underlying
/// buttons are fixed.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"
    private static let minimumTapTarget: CGFloat = 44

    private func assertAccessible(_ element: XCUIElement, name: String) {
        XCTAssertTrue(element.exists, "\(name) does not exist")
        XCTAssertFalse(element.label.isEmpty, "\(name) has no accessibility label")
        logIfBelowMinimumTapTarget(element, name: name)
    }

    private func logIfBelowMinimumTapTarget(_ element: XCUIElement, name: String) {
        let frame = element.frame
        guard frame.width < Self.minimumTapTarget || frame.height < Self.minimumTapTarget else { return }
        let size = "\(Int(frame.width))×\(Int(frame.height))pt"
        XCTContext.runActivity(named: "⚠️ \(name) is \(size), below the 44×44pt HIG minimum") { _ in }
    }

    func testSeededJourneyScreensAreAccessible() throws {
        let app = XCUIApplication()
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded") { app, destination in
            app.launchArguments += [
                "-AcaiUITestCodebaseArtifact", Self.codebaseID,
                destination.appendingPathComponent("artifacts/seeded.json").path
            ]
        }

        let browser = ProjectBrowserScreen(app: app)
        XCTAssertTrue(browser.newProjectButton.waitForExistence(timeout: 10))
        assertAccessible(browser.newProjectButton, name: "New Project button")

        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))

        // `addCodebaseButton`/`addDiagramButton` aren't audited here: on compact width they live
        // inside a toolbar `Menu`, not as directly-reachable buttons, and auditing them needs a
        // menu-opening screen-object helper this doesn't have yet.
        let detail = ProjectDetailScreen(app: app)

        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        // A sidebar re-render racing this tap can invalidate `projectRow` between find and tap.
        projectRow.tapUntil(codebaseRow)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        codebaseRow.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10))
        assertAccessible(codebaseDetail.reindexButton, name: "Reindex button")
        codebaseDetail.reindexButton.tap()

        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 30))
        let diagram = ClassDiagramScreen(app: app)
        classDiagramButton.tapUntil(diagram.typeNode(named: "Base"))

        // `fitToViewButton`/`sidebarToggleButton` aren't audited on compact width either: iOS
        // collapses the diagram toolbar's overflow behind a "More" button the screen objects don't
        // open yet. Undo/Redo happen to survive the collapse today, but that's not guaranteed.
        XCTAssertTrue(diagram.typeNode(named: "Base").waitForExistence(timeout: 15), "diagram canvas never rendered")
        XCTAssertTrue(diagram.undoButton.waitForExistence(timeout: 15))
        assertAccessible(diagram.undoButton, name: "Undo button")
        assertAccessible(diagram.redoButton, name: "Redo button")
    }
}
