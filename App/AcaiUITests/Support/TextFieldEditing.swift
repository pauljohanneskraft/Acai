import XCTest

extension XCUIElement {
    /// Clears an already-populated text field (e.g. `DeltaComparisonBar`'s ref field, which starts
    /// pre-filled with `"HEAD"`) before typing `text` — `typeText` alone would just append.
    func clearAndTypeText(_ text: String) {
        tap()
        if let currentValue = value as? String, !currentValue.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
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
}
