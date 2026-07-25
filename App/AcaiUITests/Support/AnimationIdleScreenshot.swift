import Foundation
import XCTest

@MainActor
extension XCUIApplication {
    /// Captures the frontmost window only once repeated captures stop changing, so a caller never
    /// diffs/records a golden mid-animation (a still-fading-in `Menu`, a sidebar row whose selection
    /// highlight `withAnimation`s in after the diagram content already exists, etc.). Waiting for one
    /// specific element to exist only proves that element updated, not that independently-animated
    /// siblings did too — hence polling the whole frame rather than a single targeted wait.
    func screenshotAfterAnimationsIdle(
        pollInterval: TimeInterval = 0.1, stableSamplesRequired: Int = 3, timeout: TimeInterval = 5
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
