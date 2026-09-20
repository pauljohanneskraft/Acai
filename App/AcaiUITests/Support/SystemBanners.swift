import XCTest

/// iOS posts system notifications onto a simulator at moments no test controls — on CI a "Ready for
/// Apple Intelligence" banner covered a screenshot, and one can just as well swallow a tap. Nothing
/// on the simulator turns them off, so the interaction and screenshot helpers clear any visible
/// banner first. macOS has no such banners over the app window.
@MainActor
struct SystemBanners {
    #if os(iOS)
    /// Confirmed from springboard's accessibility tree while a notification was showing.
    private var banner: XCUIElement {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .descendants(matching: .any)["NotificationShortLookView"]
    }
    #endif

    var isShowing: Bool {
        #if os(iOS)
        banner.exists
        #else
        false
        #endif
    }

    /// Fails at the caller's line if the banner won't go away, rather than tapping or capturing under it.
    ///
    /// Swipes a springboard coordinate rather than the banner element: a banner that auto-dismisses
    /// between the check above and the swipe leaves the element query with nothing to resolve, which
    /// fails the interaction itself — the outcome this wanted anyway.
    func dismiss(file: StaticString = #filePath, line: UInt = #line) {
        #if os(iOS)
        guard banner.exists else { return }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).press(
            forDuration: 0.05,
            thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0))
        )
        banner.waitForDisappearanceOrFail("the system notification banner", file: file, line: line)
        #endif
    }
}
