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

    func dismiss() {
        #if os(iOS)
        guard banner.exists else { return }
        banner.swipeUp()
        _ = banner.waitForNonExistence(timeout: 5)
        #endif
    }
}
