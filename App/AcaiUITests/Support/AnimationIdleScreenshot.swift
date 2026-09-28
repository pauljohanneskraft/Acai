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
    /// `element` narrows the capture to one element, for a screen whose surroundings vary per run.
    /// A frame that never settles is reported as a failure rather than returned quietly: comparing or
    /// recording a mid-animation capture fails by producing wrong pixels, which a passing run hides.
    /// Budgeted in samples rather than seconds alone: a capture blocks until the app is quiescent, so
    /// while a screen is still doing its on-appear work one sample costs as much as the whole wait
    /// (measured on CI: 21s then 30s for a compare panel still listing refs). A seconds-only budget
    /// then expires inside the first sample and reports a still screen as mid-animation.
    func screenshotAfterAnimationsIdle(
        of element: XCUIElement? = nil,
        pollInterval: TimeInterval = 0.3, stableSamplesRequired: Int = 2, maximumSamples: Int = 8,
        timeout: TimeInterval = .uiWork,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIScreenshot {
        let target = element ?? windows.firstMatch
        let started = Date()
        var latest = target.screenshot()
        var previous = latest.pngRepresentation
        var stableCount = 0
        var settled = false
        var samples = 1
        let deadline = started.addingTimeInterval(timeout)
        while samples < maximumSamples, Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            latest = target.screenshot()
            samples += 1
            let current = latest.pngRepresentation
            if current == previous {
                stableCount += 1
                if stableCount >= stableSamplesRequired {
                    settled = true
                    break
                }
            } else {
                stableCount = 0
            }
            previous = current
        }
        if !settled {
            XCTFail(
                """
                No \(stableSamplesRequired) consecutive captures matched in \(samples) samples over \
                \(Int(Date().timeIntervalSince(started)))s, so this capture is mid-animation
                """,
                file: file, line: line)
        }
        return latest
    }
}
