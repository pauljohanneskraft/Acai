import XCTest

@MainActor
extension XCUIElement {
    /// Clears an already-populated text field (e.g. `CompareGitPanel`'s ref field, which starts
    /// pre-filled with `"HEAD"`, or `FreeformDiagramCheckpointsView`'s save-checkpoint field,
    /// pre-filled with a timestamp) before typing `text` — `typeText` alone would just append.
    func clearAndTypeText(_ text: String) {
        tap()
        if let currentValue = value as? String, !currentValue.isEmpty {
            // A plain `tap()` on a field with existing text can leave the cursor mid-string (it taps
            // the field's center), so backspacing from wherever that lands can leave a tail fragment
            // of the old value un-deleted — confirmed empirically (a saved checkpoint named
            // "Baseline" over a prefilled timestamp came out as "Baseline08:42", the tail of the
            // timestamp the initial backspacing never reached). Tap near the field's trailing edge
            // first to move the cursor to (or past) the end, then backspace comfortably more than
            // the text's length so cursor-position drift can't leave anything behind.
            coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count + 10))
        }
        typeText(text)
    }

    /// Taps, then waits for `destination` to appear; retries the tap (up to `attempts` times) if it
    /// doesn't, splitting `timeout` across attempts. Works around an intermittent XCUITest
    /// synthesis race observed empirically: a tap landing right after a `GeometryReader`-driven
    /// layout pass (e.g. `CodebaseDetailView`'s diagram buttons, whose card height is computed from
    /// a `PreferenceKey`) can silently not reach the intended control on the first attempt, with no
    /// error — the destination screen just never appears.
    func tapUntil(_ destination: XCUIElement, timeout: TimeInterval = 9, attempts: Int = 3) {
        let perAttempt = timeout / Double(attempts)
        for _ in 0..<attempts {
            tap()
            if destination.waitForExistence(timeout: perAttempt) { return }
        }
    }

    /// Picks an option from a `Picker`-rendered popup/menu (`self`) by its literal text — a SwiftUI
    /// `Picker` in a `Form` surfaces differently per platform (a popup-button menu on macOS, a pushed
    /// list or inline menu on iOS) and the option itself has no separate identifier, so this matches
    /// by text across every plausible element kind. Matches on `label` **or** `title`: confirmed by
    /// dumping the accessibility tree that a macOS popup button's `NSMenuItem` exposes its text via
    /// the `title` attribute with `label` left empty (the opposite of most other control types here,
    /// which populate `label`) — a plain `label == %@` predicate matched nothing on macOS even though
    /// the item was genuinely present the whole time. Returns the matched option element
    /// (already waited-for) so the caller can assert its existence before tapping.
    @discardableResult
    func choose(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement {
        // A caller typically only confirmed `self` existed via an earlier, separate wait (e.g.
        // `tapUntil`) — by the time control reaches here, a still-settling sheet/config screen can
        // have re-rendered it under a stale reference. One more short wait right before the tap
        // gives it a chance to resolve again instead of failing outright.
        _ = waitForExistence(timeout: 5)
        tap()
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@", label, label)).firstMatch
        _ = option.waitForExistence(timeout: timeout)
        option.tap()
        return option
    }
}
