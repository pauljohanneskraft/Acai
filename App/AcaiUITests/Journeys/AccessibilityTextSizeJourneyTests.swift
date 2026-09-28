import XCTest

/// Proves layouts hold at the largest accessibility text size (#203), the same way
/// `GermanLayoutJourneyTests` proves it for the longest shipped language: walk the densest screens
/// with the size forced to `accessibility5` and diff each against its own golden. A pixel diff is
/// the only check that catches a node box or a settings row that no longer fits its (now much
/// larger) content — an accessibility-label assertion would pass on a string that actually got
/// clipped or overlapped on screen.
@MainActor
final class AccessibilityTextSizeJourneyTests: UIJourneyTestCase {
    func testClassDiagramHoldsAtTheLargestAccessibilityTextSize() throws {
        // Canned: what this proves is the layout at `accessibility5`, and the canned artifact carries
        // the same four types a parse would — `SeededFixtureContractTests` keeps the two in step.
        let codebaseDetail = openPreindexedSeededCodebase(dynamicTypeSize: "accessibility5")
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)

        diagram.typeNode(named: "Base").waitOrFail("the Base type node", timeout: .uiWork)
        for name in ["Derived", "Helper", "Worker"] {
            diagram.typeNode(named: name).waitOrFail("\(name), drawn alongside Base")
        }
        // See `ScreenshotJourneyTests`: the initial centring races the status bar hiding.
        diagram.tapFitToView()

        validateScreenshot("ClassDiagram", state: "accessibility5")
    }
}
