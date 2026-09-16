import XCTest

@MainActor
extension XCUIElement {
    /// `typeText` alone would just append to an already-populated field.
    func clearAndTypeText(_ text: String) {
        tap()
        if let currentValue = value as? String, !currentValue.isEmpty {
            // A plain `tap()` can leave the cursor mid-string (it taps the field's center), so
            // backspacing from wherever that lands can leave a tail fragment un-deleted (confirmed
            // empirically: "Baseline" over a prefilled timestamp came out as "Baseline08:42"). Tap
            // near the trailing edge first to move the cursor to (or past) the end, then backspace
            // comfortably more than the text's length so cursor-position drift can't leave anything.
            coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count + 10))
        }
        typeText(text)
    }

    /// Retries the tap (up to `attempts` times) if `destination` doesn't appear, splitting
    /// `timeout` across attempts. Works around an intermittent XCUITest synthesis race observed
    /// empirically: a tap landing right after a `GeometryReader`-driven layout pass can silently
    /// not reach the intended control on the first attempt, with no error.
    ///
    /// Skips (not taps) an attempt where `self` isn't hittable yet — a fired tap records an XCTest
    /// failure immediately even if a later attempt would have succeeded, so this can't just call
    /// `tapWhenHittable`.
    func tapUntil(_ destination: XCUIElement, timeout: TimeInterval = 9, attempts: Int = 3) {
        let perAttempt = timeout / Double(attempts)
        for _ in 0..<attempts {
            if pollUntilHittable(timeout: perAttempt) {
                tap()
            }
            if destination.waitForExistence(timeout: perAttempt) { return }
        }
    }

    /// Taps once, then waits for `self` to leave the screen — for a control that navigates away once
    /// the tap lands *and* whose action isn't idempotent (the diagram buttons call `diagrams.add`,
    /// so every landed tap creates another diagram).
    ///
    /// `tapUntil` can't be used there: it retries until the *destination* appears, so a first tap
    /// that landed but is still rendering gets tapped again and creates a duplicate. A retry loop
    /// keyed on `self` disappearing has the same flaw the moment disappearance is merely slow: a
    /// tap that already landed but hasn't cleared the screen within one `settle` window looks
    /// identical to a tap that never landed, so a naive retry there taps again anyway and creates a
    /// duplicate diagram. Tapping exactly once and spending the whole `settle * attempts` budget on
    /// one wait avoids that: a slow-but-successful action still has time to finish, and a tap that
    /// truly never landed leaves `self` on screen so the caller's next assertion fails with a clear
    /// "never appeared" message instead of the screen silently carrying an extra diagram.
    func tapUntilItDisappears(settle: TimeInterval = 8, attempts: Int = 3) {
        guard pollUntilHittable(timeout: settle) else { return }
        tap()
        _ = waitForNonExistence(timeout: settle * Double(attempts))
    }

    /// Waits for `self` to be hittable, not just present, before tapping. Confirmed empirically: an
    /// element can already `exist` while still reporting a stale zero-size, off-screen frame from
    /// before a layout pass lands, failing a plain `tap()` with "Not hittable" even though
    /// `waitForExistence` already returned true.
    func tapWhenHittable(timeout: TimeInterval = 5, pollInterval: TimeInterval = 0.2) {
        _ = pollUntilHittable(timeout: timeout, pollInterval: pollInterval)
        tap()
    }

    /// Polls `isHittable` without tapping, returning whether it settled before `timeout`. Real
    /// `Thread.sleep` between reads, not `XCTNSPredicateExpectation`: `XCUIElement` isn't
    /// KVO-compliant, so a predicate expectation on `isHittable` latches its first evaluation
    /// instead of re-querying (confirmed empirically).
    private func pollUntilHittable(timeout: TimeInterval, pollInterval: TimeInterval = 0.2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return isHittable
    }

    /// Picks an option from a `Picker`-rendered popup/menu (`self`) by its literal text — the
    /// option itself has no separate identifier, so this matches by text across every plausible
    /// element kind. Matches on `label` **or** `title`: confirmed by dumping the accessibility tree
    /// that a macOS popup button's `NSMenuItem` exposes its text via `title` with `label` left
    /// empty (the opposite of most other control types here) — a plain `label == %@` predicate
    /// matched nothing on macOS even though the item was genuinely present.
    @discardableResult
    func choose(
        _ label: String, in app: XCUIApplication, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        // A caller typically only confirmed `self` existed via an earlier, separate wait — by the
        // time control reaches here, a still-settling sheet/config screen can have re-rendered it
        // under a stale reference. One more short wait gives it a chance to resolve again.
        waitOrFail("the control offering '\(label)'", file: file, line: line)
        tap()
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@", label, label)).firstMatch
        option.waitOrFail("option '\(label)'", timeout: timeout, file: file, line: line)
        option.tap()
        return option
    }
}
