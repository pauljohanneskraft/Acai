import XCTest

/// Covers #183 ("Find a node in a diagram") against the seeded fixture's known
/// `Base`/`Derived`/`Helper`/`Worker` types: searching narrows the match count, an unmatched query
/// reports no matches, and dismissing search returns the diagram to normal without touching its
/// nodes.
@MainActor
final class ClassDiagramSearchJourneyTests: UIJourneyTestCase {
    /// Types `text` (onto the query when `appending`) until the summary reads `expected`; repeats don't change it.
    private func search(
        _ diagram: ClassDiagramScreen, for text: String, appending: Bool = false, expecting expected: String,
        attempts: Int = 3, file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<attempts {
            if appending {
                diagram.searchField.tapWhenReady("the search field", file: file, line: line)
                diagram.searchField.typeText(text)
            } else {
                diagram.searchField.clearAndTypeText(text, file: file, line: line)
            }
            if diagram.searchMatchSummary(reading: expected).appears(within: .uiTransition / 2) { return }
        }
        XCTFail("searching for '\(text)' never reported '\(expected)'", file: file, line: line)
    }

    private func assertTypeNodesDrawn(
        _ diagram: ClassDiagramScreen, _ names: [String], _ expectation: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let missing = names.filter { !diagram.typeNode(named: $0).exists }
        XCTAssertTrue(missing.isEmpty, "\(missing.joined(separator: ", ")) should \(expectation)", file: file, line: line)
    }

    func testFindNodeByNameNarrowsAndDismissRestoresTheDiagram() throws {
        let codebaseDetail = openPreindexedSeededCodebase()
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)

        // One wait for both "Base is drawn" and "Base reaches VoiceOver".
        diagram.describedTypeNode(named: "Base")
            .waitOrFail("the Base type node, described to VoiceOver", timeout: .uiWork)
        assertTypeNodesDrawn(diagram, ["Derived", "Helper", "Worker"], "be drawn alongside Base")
        diagram.relationship(from: "Derived", to: "Base", describing: "Inheritance")
            .waitOrFail("the Derived → Base relationship, described to VoiceOver as inheritance")
        // See `SeededProjectWalkthroughJourneyTests`: the initial centring races the status bar hiding.
        diagram.tapFitToView()

        diagram.openSearch()

        // "Base" matches exactly one of the seeded fixture's four types; counts and stepping are
        // `ClassDiagramViewModelTests` and `DiagramSearchSummaryTests`.
        search(diagram, for: "Base", expecting: "1 match")
        validateScreenshot("ClassDiagram", state: "searching")

        diagram.searchNextButton.tapWhenReady("the search's Next Match button")
        diagram.searchPreviousButton.tapWhenReady("the search's Previous Match button")

        // Wherever the tap leaves the cursor, "XYZ" inside "Base" matches nothing, with no burst of deletes first.
        search(diagram, for: "XYZ", appending: true, expecting: "No matches")

        diagram.searchDismissButton.tapWhenReady("the search's Dismiss button")
        diagram.searchField.waitForDisappearanceOrFail("the search field after dismissing search")
        // Dismissing search touches only the search UI's own state.
        assertTypeNodesDrawn(diagram, ["Base", "Derived", "Helper", "Worker"], "survive dismissing search")
    }
}
