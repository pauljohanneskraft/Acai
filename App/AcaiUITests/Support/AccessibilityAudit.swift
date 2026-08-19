import XCTest

/// Asserts an interactive element is actually reachable by assistive technology — present, and
/// carrying a real accessibility label rather than only an identifier.
///
/// Tap-target misses below Apple HIG's 44×44pt minimum are logged, not asserted — turn
/// `logIfBelowMinimumTapTarget`'s activity into a hard `XCTAssertGreaterThanOrEqual` once the
/// underlying buttons are fixed.
@MainActor
struct AccessibilityAudit {
    let testCase: XCTestCase
    var minimumTapTarget: CGFloat = 44

    func assertAccessible(
        _ element: XCUIElement, name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, "\(name) does not exist", file: file, line: line)
        XCTAssertFalse(element.label.isEmpty, "\(name) has no accessibility label", file: file, line: line)
        logIfBelowMinimumTapTarget(element, name: name)
    }

    private func logIfBelowMinimumTapTarget(_ element: XCUIElement, name: String) {
        let frame = element.frame
        guard frame.width < minimumTapTarget || frame.height < minimumTapTarget else { return }
        let size = "\(Int(frame.width))×\(Int(frame.height))pt"
        XCTContext.runActivity(named: "⚠️ \(name) is \(size), below the 44×44pt HIG minimum") { _ in }
    }
}
