import XCTest

extension TimeInterval {
    /// An element that follows directly from the previous interaction: navigation, a sheet, a menu.
    /// Measured on CI, a transition either lands within ~5s or never does, so waiting longer only
    /// delays the failure.
    static let uiTransition: TimeInterval = 10
    /// Real work behind the interaction: indexing, cloning, loading a comparison.
    static let uiWork: TimeInterval = 60
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
