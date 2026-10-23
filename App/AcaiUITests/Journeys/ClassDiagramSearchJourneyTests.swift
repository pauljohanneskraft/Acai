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

    /// Asserts every one of `names` is drawn, in a single accessibility-tree snapshot. Only a run
    /// that is already failing pays a query per name, to report which of them is missing.
    private func assertTypeNodesDrawn(
        _ diagram: ClassDiagramScreen, _ names: [String], _ expectation: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let drawn = diagram.typeNodes(named: names).count
        if drawn == names.count { return }
        let missing = names.filter { !diagram.typeNode(named: $0).exists }
        let detail = missing.isEmpty ? "\(drawn) of \(names.count) matched" : missing.joined(separator: ", ")
        XCTFail(
            "\(detail) — every one of \(names.joined(separator: ", ")) should \(expectation)",
            file: file, line: line)
    }

    func testFindNodeByNameNarrowsAndDismissRestoresTheDiagram() throws {
        let codebaseDetail = openPreindexedSeededCodebase()
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)

        // The described node matches the plain node's identifier plus its VoiceOver label and value,
        // so this one wait covers both "the diagram has drawn Base" and "Base reaches VoiceOver".
        diagram.describedTypeNode(named: "Base")
            .waitOrFail("the Base type node, described to VoiceOver", timeout: .uiWork)
        assertTypeNodesDrawn(diagram, ["Derived", "Helper", "Worker"], "be drawn alongside Base")
        diagram.relationship(from: "Derived", to: "Base", describing: "Inheritance")
            .waitOrFail("the Derived → Base relationship, described to VoiceOver as inheritance")
        // See `SeededProjectWalkthroughJourneyTests`: the initial centring races the status bar hiding.
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
        assertTypeNodesDrawn(diagram, ["Base", "Derived", "Helper", "Worker"], "survive dismissing search")
    }
}
