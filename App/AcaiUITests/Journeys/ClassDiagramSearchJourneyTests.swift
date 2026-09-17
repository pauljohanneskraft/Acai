import XCTest

/// Covers #183 ("Find a node in a diagram") against the seeded fixture's known
/// `Base`/`Derived`/`Helper`/`Worker` types: searching narrows the match count, an unmatched query
/// reports no matches, and dismissing search returns the diagram to normal without touching its
/// nodes.
@MainActor
final class ClassDiagramSearchJourneyTests: UIJourneyTestCase {
    /// Types `text` and waits for the match summary to catch up, retyping if it never arrives: a
    /// query landing while the diagram's own state is still settling from the previous action can be
    /// missed by SwiftUI's diffing, and a plain wait can't recover from that. Retyping is idempotent.
    private func search(
        _ diagram: ClassDiagramScreen, for text: String, expecting expected: String, attempts: Int = 3,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<attempts {
            diagram.searchField.clearAndTypeText(text, file: file, line: line)
            if diagram.searchMatchSummary(reading: expected).appears(within: .uiTransition / 2) { return }
        }
        XCTFail("searching for '\(text)' never reported '\(expected)'", file: file, line: line)
    }

    func testFindNodeByNameNarrowsAndDismissRestoresTheDiagram() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .parsed)
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)

        diagram.typeNode(named: "Base").waitOrFail("the Base type node", timeout: .uiWork)
        for name in ["Derived", "Helper", "Worker"] {
            XCTAssertTrue(diagram.typeNode(named: name).exists, "\(name) should be drawn alongside Base")
        }
        // See `ScreenshotJourneyTests`: the initial centring races the status bar hiding.
        diagram.tapFitToView()

        diagram.openSearch()

        // "Base" matches exactly one of the seeded fixture's four types.
        search(diagram, for: "Base", expecting: "1 match")
        validateScreenshot("ClassDiagram", state: "searching")

        // "er" matches Derived, Helper and Worker but not Base.
        search(diagram, for: "er", expecting: "3 matches")

        // Stepping through matches never crashes or disables itself once there are matches to step
        // through.
        diagram.searchNextButton.tapWhenReady("the search's Next Match button")
        diagram.searchPreviousButton.tapWhenReady("the search's Previous Match button")

        // A query nothing matches reports that plainly rather than looking identical to "not
        // searching yet".
        search(diagram, for: "nonexistentXYZ", expecting: "No matches")

        diagram.searchDismissButton.tapWhenReady("the search's Dismiss button")
        diagram.searchField.waitForDisappearanceOrFail("the search field after dismissing search")
        // Dismissing search touches only the search UI's own state — every node from before is
        // still exactly where it was.
        for name in ["Base", "Derived", "Helper", "Worker"] {
            XCTAssertTrue(diagram.typeNode(named: name).exists, "\(name) should survive dismissing search")
        }
    }
}
