import XCTest

/// Content (churn/complexity math, the three `HotspotViewModel.load` branches) is covered by
/// `HotspotViewModelTests`; this only proves the screen opens, finishes loading and its toolbar responds.
@MainActor
final class HotspotJourneyTests: UIJourneyTestCase {
    func testHotspotScreenOpensAndTogglesItsSidebar() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .canned)
        let hotspot = codebaseDetail.createDiagram(type: "hotspot", as: HotspotScreen.self)

        // The seeded fixture isn't a git repository, so loading ends in the "no git history" state.
        hotspot.noGitHistoryState.waitOrFail("the hotspot screen's no-git-history state", timeout: .uiWork)

        hotspot.tapToolbarButton(hotspot.sidebarToggleButton, label: "Sidebar")
    }
}
