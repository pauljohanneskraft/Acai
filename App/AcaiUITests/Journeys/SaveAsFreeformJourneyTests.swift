import XCTest

@MainActor
final class SaveAsFreeformJourneyTests: UIJourneyTestCase {
    /// Focus roots at `Base`, which depends on none of the other seeded types, so only `Base` is on screen.
    func testCopyContainsOnlyTheTypesTheFocusedDiagramShows() throws {
        let codebaseDetail = openIndexedSeededCodebase()
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
        diagram.typeNode(named: "Base").waitOrFail("the Base type node", timeout: .uiWork)

        diagram.enableFocus()

        let freeform = diagram.saveAsFreeform()
        freeform.typeNode(named: "Base").waitOrFail("Base in the freeform copy")
        for hidden in ["Derived", "Helper", "Worker"] {
            XCTAssertFalse(
                freeform.typeNode(named: hidden).exists, "\(hidden) was hidden by focus but appeared in the copy"
            )
        }
    }
}
