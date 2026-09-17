import XCTest
#if os(iOS)
import UIKit
#endif

/// Shared lifecycle for every journey: owns the app under test, stops at the first behavioral
/// failure, reports screenshot drift without truncating the journey, and attaches diagnostics.
@MainActor
class UIJourneyTestCase: XCTestCase {
    let app = XCUIApplication()

    private var screenshotFailures: [(message: String, file: StaticString, line: UInt)] = []

    // The `async` overrides, unlike the synchronous ones, inherit this class's `@MainActor`.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        screenshotFailures = []
        pinOrientation()
    }

    override func tearDown() async throws {
        // Otherwise the first reported drift aborts teardown before the app is terminated.
        continueAfterFailure = true
        for failure in screenshotFailures {
            XCTFail(failure.message, file: failure.file, line: failure.line)
        }
        if (testRun?.failureCount ?? 0) > 0 {
            attachDiagnostics()
        }
        app.terminate()
        try await super.tearDown()
    }

    /// Captures the frontmost window once it stops changing and compares it against its golden.
    /// Drift is reported at the end of the test rather than immediately, so one drifted state never
    /// prevents the states after it from being captured for `Scripts/snapshots_accept.sh`.
    func validateScreenshot(
        _ viewType: String, state: String, maxChangedFraction: Double? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let comparator = ScreenshotComparator(
            goldenDirectory: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("__Snapshots__"),
            maxChangedFraction: maxChangedFraction
        )
        let banners = SystemBanners()
        banners.dismiss(file: file, line: line)
        var screenshot = app.screenshotAfterAnimationsIdle()
        // A banner can also arrive while the capture waits for animations to settle.
        if banners.isShowing {
            banners.dismiss(file: file, line: line)
            screenshot = app.screenshotAfterAnimationsIdle()
        }
        if let failure = comparator.validate(viewType: viewType, state: state, screenshot: screenshot, testCase: self) {
            screenshotFailures.append((failure, file, line))
        }
    }

    /// Orientation is simulator-wide and outlives a test, so every iPad journey runs landscape and
    /// the rotation only ever happens once per simulator boot.
    private func pinOrientation() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad, XCUIDevice.shared.orientation != .landscapeLeft {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        #endif
    }

    private func attachDiagnostics() {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "\(name) — screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name) — element tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
