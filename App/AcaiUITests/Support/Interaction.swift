import XCTest

extension TimeInterval {
    /// An element that follows directly from the previous interaction: navigation, a sheet, a menu.
    /// Measured on CI, a transition either lands within ~5s or never does, so waiting longer only
    /// delays the failure.
    static let uiTransition: TimeInterval = 10
    /// Real work behind the interaction: indexing, cloning, loading a comparison. Sized for CI's
    /// slowest case, a real-git comparison extraction on the iPad runner.
    static let uiWork: TimeInterval = 90
}

/// The only ways a journey waits for or touches an element. Every helper fails at the caller's line
/// with a description of what was expected, and — since `UIJourneyTestCase` stops at the first
/// failure — never lets a missed step cascade into unrelated errors further down.
@MainActor
extension XCUIElement {
    @discardableResult
    func waitOrFail(
        _ description: String, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        if !waitForExistence(timeout: timeout) {
            XCTFail("\(description) never appeared", file: file, line: line)
        }
        return self
    }

    /// A non-failing wait, only for a retry loop that recovers from a miss itself (e.g. retyping a
    /// query) and reports the final miss through `waitOrFail`.
    func appears(within timeout: TimeInterval) -> Bool {
        waitForExistence(timeout: timeout)
    }

    func waitForDisappearanceOrFail(
        _ description: String, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        if !waitForNonExistence(timeout: timeout) {
            XCTFail("\(description) never went away", file: file, line: line)
        }
    }

    /// Waits until the element can take a tap: it exists and is hittable — an element can exist with a
    /// stale zero-size frame before layout lands, or sit under a menu or popover. An element scrolled
    /// out of view never reports hittable (`tap()` scrolls to it), so one lying outside the window is
    /// ready too.
    ///
    /// Every query snapshots the app's accessibility tree, which on a CI simulator takes long enough
    /// that tight polling slows the app under test and times queries out (measured: the suite ran ~40%
    /// slower polling several queries every 0.1s). So: one existence wait, then one hit-test per
    /// quarter second.
    func waitUntilReady(
        _ description: String, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        guard waitForExistence(timeout: timeout) else {
            XCTFail("\(description) never appeared", file: file, line: line)
            return
        }
        var window: CGRect?
        while Date() < deadline {
            if isHittable { return }
            let windowFrame = window ?? XCUIApplication().windows.firstMatch.frame
            window = windowFrame
            if exists, !frame.isEmpty, !windowFrame.contains(frame) { return }
            // `XCUIElement` isn't KVO-compliant, so a predicate expectation would latch its first read.
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("\(description) never became tappable", file: file, line: line)
    }

    /// Taps exactly once. Use this for anything with a side effect (creating, deleting, toggling).
    func tapWhenReady(
        _ description: String, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        waitUntilReady(description, timeout: timeout, file: file, line: line)
        tap()
    }

    /// Taps, and taps again only while `destination` hasn't appeared. Only for idempotent navigation
    /// (selecting a row, opening a sheet) — a retried create action makes a duplicate.
    func tap(
        _ description: String, until destination: XCUIElement, attempts: Int = 3,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(.uiTransition)
        let perAttempt = TimeInterval.uiTransition / Double(attempts)
        for _ in 0..<attempts {
            waitUntilReady(description, timeout: max(deadline.timeIntervalSinceNow, 1), file: file, line: line)
            tap()
            if destination.waitForExistence(timeout: min(perAttempt, max(deadline.timeIntervalSinceNow, 1))) {
                return
            }
            if !exists || Date() >= deadline { break }
        }
        destination.waitOrFail(
            "the destination of tapping \(description)", timeout: max(deadline.timeIntervalSinceNow, 1),
            file: file, line: line
        )
    }

    /// Waits for `self` to go away, failing immediately with `failure`'s label if that appears first —
    /// for an operation whose success dismisses its own screen and whose failure shows an alert.
    func waitForDisappearanceOrFail(
        _ description: String, failingOn failure: XCUIElement, timeout: TimeInterval = .uiWork,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while deadline.timeIntervalSinceNow > 0 {
            if waitForNonExistence(timeout: min(1, deadline.timeIntervalSinceNow)) { return }
            if failure.exists {
                XCTFail("\(description) failed: \(failure.label)", file: file, line: line)
                return
            }
        }
        XCTFail("\(description) never went away", file: file, line: line)
    }
}

@MainActor
extension XCUIApplication {
    /// Cancels a popover-style presentation (e.g. a `.confirmationDialog` on iPad), which has no
    /// Cancel button. The dismiss region spans the whole window, popover included, so its center can
    /// land on the popover itself and do nothing; this taps the region's corner farthest from
    /// `content`, inset away from the screen edges.
    func dismissPopover(showing content: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let region = otherElements["PopoverDismissRegion"]
        content.waitUntilReady("the popover's content", file: file, line: line)
        region.waitUntilReady("the popover's dismiss region", file: file, line: line)
        let bounds = region.frame
        let offset = CGVector(
            dx: content.frame.midX > bounds.midX ? 0.15 : 0.85,
            dy: content.frame.midY > bounds.midY ? 0.2 : 0.8
        )
        region.coordinate(withNormalizedOffset: offset).tap()
        region.waitForDisappearanceOrFail("the popover", file: file, line: line)
    }
}
