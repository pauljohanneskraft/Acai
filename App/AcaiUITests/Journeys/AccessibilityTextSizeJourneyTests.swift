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
        let codebaseDetail = openIndexedSeededCodebase(analysis: .parsed, dynamicTypeSize: "accessibility5")
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)

        diagram.typeNode(named: "Base").waitOrFail("the Base type node", timeout: .uiWork)
        for name in ["Derived", "Helper", "Worker"] {
            XCTAssertTrue(diagram.typeNode(named: name).exists, "\(name) should be drawn alongside Base")
        }
        // See `ScreenshotJourneyTests`: the initial centring races the status bar hiding.
        diagram.tapFitToView()

        validateScreenshot("ClassDiagram", state: "accessibility5")
    }
}
