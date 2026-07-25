import Foundation
import XCTest

extension XCUIApplication {
    /// Captures the frontmost window only once repeated captures stop changing, so a caller never
    /// diffs/records a golden mid-animation (a still-fading-in `Menu`, a sidebar row whose selection
    /// highlight `withAnimation`s in after the diagram content already exists, etc.).
    ///
    /// Root-caused via the determinism check (`TESTING_ARCHITECTURE.md`): two consecutive, otherwise
    /// unchanged recording runs produced `ClassDiagram/iPad/populated.png`/`inspectorOpen.png` (a
    /// sidebar row's selection pill present in one capture, absent in the other) and
    /// `ProjectDetail/iPhone/addMenuOpen.png` (the `Menu` presentation) with several percent of
    /// perceptual drift. For the ClassDiagram pair, the cause is two independent, uncoordinated
    /// SwiftUI transactions racing each other: `diagramButton` (`CodebaseDetailView.swift`) inserts
    /// a brand-new `GeneratedDiagram` (an animated `withAnimation` insert into the sidebar's
    /// `ForEach`, via `persistChanges()`) and then sets `model.selection` to point at it as a
    /// *separate*, unwrapped `@Published` change that drives `List(selection:)`'s own
    /// selection-highlight animation — neither transaction is tied to the other or to the detail
    /// pane becoming ready, so a test that only waits for the detail pane's content
    /// (`waitForExistence` on a node/menu item) can capture before either the insert or the
    /// highlight animation has settled. Waiting for a specific element existing only proves that one
    /// element updated, not that its independently-animated siblings did too — hence polling for the
    /// whole frame to stop changing, rather than adding another targeted wait.
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
