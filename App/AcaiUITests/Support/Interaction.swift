import XCTest

extension TimeInterval {
    /// An element that follows directly from the previous interaction: navigation, a sheet, a menu.
    /// The transition itself lands within a few seconds or never, but on a loaded CI simulator a single
    /// accessibility query was measured at ~9s, so the budget has to cover query latency, not just the
    /// transition. A wait returns as soon as its condition holds, so this only lengthens real failures.
    static let uiTransition: TimeInterval = 30
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
        // Checked at least once even if a slow existence query used up the deadline.
        repeat {
            if isHittable { return }
            let windowFrame = window ?? XCUIApplication().windows.firstMatch.frame
            window = windowFrame
            if exists, !frame.isEmpty, !windowFrame.contains(frame) { return }
            // `XCUIElement` isn't KVO-compliant, so a predicate expectation would latch its first read.
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        XCTFail("\(description) never became tappable", file: file, line: line)
    }

    /// A control enabled by input it depends on (a typed token, a picked option) updates a render pass
    /// after that input, so an instant `isEnabled` read can still see it disabled.
    func waitUntilEnabled(
        _ description: String, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        waitOrFail(description, timeout: timeout, file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isEnabled { return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        XCTFail("\(description) never became enabled", file: file, line: line)
    }

    /// Taps exactly once. Use this for anything with a side effect (creating, deleting, toggling).
    func tapWhenReady(
        _ description: String, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        waitUntilReady(description, timeout: timeout, file: file, line: line)
        SystemBanners().dismiss(file: file, line: line)
        tap()
    }

    /// Taps, and taps again only while `destination` hasn't appeared. Only for idempotent navigation
    /// (selecting a row, opening a sheet) — a retried create action makes a duplicate.
    ///
    /// Each wait keeps its own budget rather than sharing one deadline: a single slow query on a loaded
    /// CI simulator would otherwise consume the whole budget and fail a tap that was never attempted.
    func tap(
        _ description: String, until destination: XCUIElement, attempts: Int = 3,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<attempts {
            waitUntilReady(description, file: file, line: line)
            SystemBanners().dismiss(file: file, line: line)
            tap()
            if destination.waitForExistence(timeout: .uiTransition / Double(attempts)) { return }
            if !exists { break }
        }
        destination.waitOrFail("the destination of tapping \(description)", file: file, line: line)
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
    /// Tapping the region is idempotent, so a tap the presentation swallowed while it was still
    /// settling is retried rather than failing the journey.
    func dismissPopover(
        showing content: XCUIElement, attempts: Int = 3,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let region = otherElements["PopoverDismissRegion"]
        content.waitUntilReady("the popover's content", file: file, line: line)
        region.waitUntilReady("the popover's dismiss region", file: file, line: line)
        let bounds = region.frame
        let offset = CGVector(
            dx: content.frame.midX > bounds.midX ? 0.15 : 0.85,
            dy: content.frame.midY > bounds.midY ? 0.2 : 0.8
        )
        for _ in 0..<attempts {
            SystemBanners().dismiss(file: file, line: line)
            region.coordinate(withNormalizedOffset: offset).tap()
            if region.waitForNonExistence(timeout: .uiTransition / Double(attempts)) { return }
        }
        region.waitForDisappearanceOrFail("the popover", file: file, line: line)
    }
}
