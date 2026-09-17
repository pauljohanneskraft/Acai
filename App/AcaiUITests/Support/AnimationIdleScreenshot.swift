import Foundation
import XCTest

@MainActor
extension XCUIApplication {
    /// Captures the frontmost window only once repeated captures stop changing, so a caller never
    /// diffs/records a golden mid-animation. Waiting for one specific element to exist only proves
    /// that element updated, not that independently-animated siblings did too — hence polling the
    /// whole frame rather than a single targeted wait. Each capture is expensive on a CI simulator —
    /// capturing every 0.1s timed a screenshot request out — yet the interval must stay under half a
    /// text cursor's ~1s blink cycle, or consecutive captures of a focused field alternate forever.
    func screenshotAfterAnimationsIdle(
        pollInterval: TimeInterval = 0.3, stableSamplesRequired: Int = 2, timeout: TimeInterval = 10
    ) -> XCUIScreenshot {
        var latest = windows.firstMatch.screenshot()
        var previous = latest.pngRepresentation
        var stableCount = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            latest = windows.firstMatch.screenshot()
            let current = latest.pngRepresentation
            if current == previous {
                stableCount += 1
                if stableCount >= stableSamplesRequired { break }
            } else {
                stableCount = 0
            }
            previous = current
        }
        return latest
    }
}
