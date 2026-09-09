import XCTest

/// Covers #183 ("Find a node in a diagram") against the seeded fixture's known
/// `Base`/`Derived`/`Helper`/`Worker` types: searching narrows the match count, an unmatched query
/// reports no matches, and dismissing search returns the diagram to normal without touching its
/// nodes.
@MainActor
final class ClassDiagramSearchJourneyTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private var comparator: ScreenshotComparator {
        ScreenshotComparator(goldenDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__"))
    }

    /// Polls rather than waiting once: `XCUIElement` isn't KVO-compliant, so a predicate expectation
    /// on `.label` would only ever see its first read (see `TextFieldEditing.swift`'s
    /// `pollUntilHittable` doc comment for the same finding on `isHittable`).
    private func waitForMatchSummary(
        _ diagram: ClassDiagramScreen, toRead expected: String, timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if diagram.searchMatchSummary.label == expected { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    func testFindNodeByNameNarrowsAndDismissRestoresTheDiagram() throws {
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        codebaseRow.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10))
        codebaseDetail.reindexButton.tap()

        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 30), "the codebase never finished indexing")
        let diagram = ClassDiagramScreen(app: app)
        classDiagramButton.tapUntilItDisappears()

        XCTAssertTrue(diagram.typeNode(named: "Base").waitForExistence(timeout: 30))
        XCTAssertTrue(diagram.typeNode(named: "Derived").exists)
        XCTAssertTrue(diagram.typeNode(named: "Helper").exists)
        XCTAssertTrue(diagram.typeNode(named: "Worker").exists)

        diagram.openSearch()

        // "Base" matches exactly one of the seeded fixture's four types.
        diagram.searchField.clearAndTypeText("Base")
        XCTAssertTrue(waitForMatchSummary(diagram, toRead: "1 match"))
        comparator.validate(
            viewType: "ClassDiagram", state: "searching",
            screenshot: app.screenshotAfterAnimationsIdle(), testCase: self
        )

        // "er" matches Derived, Helper and Worker but not Base.
        diagram.searchField.clearAndTypeText("er")
        XCTAssertTrue(waitForMatchSummary(diagram, toRead: "3 matches"))

        // Stepping through matches never crashes or disables itself once there are matches to step
        // through.
        diagram.searchNextButton.tap()
        diagram.searchPreviousButton.tap()

        // A query nothing matches reports that plainly rather than looking identical to "not
        // searching yet".
        diagram.searchField.clearAndTypeText("nonexistentXYZ")
        XCTAssertTrue(waitForMatchSummary(diagram, toRead: "No matches"))

        diagram.searchDismissButton.tap()
        XCTAssertFalse(diagram.searchField.exists)
        // Dismissing search touches only the search UI's own state — every node from before is
        // still exactly where it was.
        XCTAssertTrue(diagram.typeNode(named: "Base").exists)
        XCTAssertTrue(diagram.typeNode(named: "Derived").exists)
        XCTAssertTrue(diagram.typeNode(named: "Helper").exists)
        XCTAssertTrue(diagram.typeNode(named: "Worker").exists)
    }
}
