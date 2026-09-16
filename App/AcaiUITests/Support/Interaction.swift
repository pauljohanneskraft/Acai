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

    /// Waits until the element exists with a real frame that held still — a control can exist with a
    /// stale zero-size frame before layout lands, and a tap landing mid-layout is silently dropped.
    /// It must also be hittable, unless it lies outside the window: an element scrolled out of view
    /// never reports hittable, and `tap()` scrolls to it. One inside the window that isn't hittable is
    /// covered (a menu, a popover) and is not ready.
    func waitUntilReady(
        _ description: String, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var previousFrame: CGRect?
        var stableSamples = 0
        while Date() < deadline {
            let currentFrame = exists ? frame : nil
            if let currentFrame, !currentFrame.isEmpty, currentFrame == previousFrame {
                stableSamples += 1
                if isHittable { return }
                let window = XCUIApplication().windows.firstMatch.frame
                if stableSamples >= 5, !window.contains(currentFrame) { return }
            } else {
                stableSamples = 0
            }
            previousFrame = currentFrame
            // `XCUIElement` isn't KVO-compliant, so a predicate expectation would latch its first read.
            Thread.sleep(forTimeInterval: 0.1)
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
        let perAttempt = TimeInterval.uiTransition / Double(attempts)
        for _ in 0..<attempts {
            waitUntilReady(description, file: file, line: line)
            tap()
            if destination.waitForExistence(timeout: perAttempt) { return }
            if !exists { break }
        }
        destination.waitOrFail("the destination of tapping \(description)", file: file, line: line)
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
        region.waitUntilReady("the popover's dismiss region", file: file, line: line)
        content.waitOrFail("the popover's content", file: file, line: line)
        let bounds = region.frame
        let offset = CGVector(
            dx: content.frame.midX > bounds.midX ? 0.15 : 0.85,
            dy: content.frame.midY > bounds.midY ? 0.2 : 0.8
        )
        region.coordinate(withNormalizedOffset: offset).tap()
        region.waitForDisappearanceOrFail("the popover", file: file, line: line)
    }
}
