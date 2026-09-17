import XCTest

/// In the seeded fixture only `Helper` (held by `Derived`) and `Worker` (held by `Helper`) have a
/// dependent — inheritance isn't counted — so the alphabetical tie-break makes `Helper` the most
/// depended-upon stop.
@MainActor
final class GuidedRouteJourneyTests: UIJourneyTestCase {

    func testFirstIndexOffersARouteWhoseStopOpensItsDiagram() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .parsed)
        codebaseDetail.guidedRouteCard.waitOrFail("the guided route card after a first index", timeout: .uiWork)
        XCTAssertFalse(codebaseDetail.guidedRouteButton.exists, "the header button is redundant while the card shows")

        let diagram = codebaseDetail.openGuidedRouteStop(kind: "mostDependedUpon", as: ClassDiagramScreen.self)
        diagram.typeNode(named: "Helper").waitOrFail("the focused Helper type node", timeout: .uiWork)
        diagram.typeNode(named: "Derived").waitOrFail("Helper's dependent Derived")
    }

    func testHidingTheRouteKeepsItAvailableFromTheHeader() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .parsed)
        codebaseDetail.guidedRouteCard.waitOrFail("the guided route card after a first index", timeout: .uiWork)

        codebaseDetail.hideGuidedRoute()
        codebaseDetail.showGuidedRoute()
        codebaseDetail.guidedRouteStop(kind: "mostDependedUpon").waitOrFail("the most depended-upon stop")
    }
}
