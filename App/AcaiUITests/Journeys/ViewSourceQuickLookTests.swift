import XCTest

/// End-to-end coverage confirming tapping "View Source" on a `ViolationRowView` opens the target
/// file in Quick Look. The seeded fixture's `SampleSwiftPackage` codebase is wired to
/// `Fixtures/seeded/quality.yml` (a budget with `max: 0` that trips on any method at all),
/// guaranteeing at least one Quality Check finding to exercise this against.
@MainActor
final class ViewSourceQuickLookTests: UIJourneyTestCase {

    func testViewSourceOpensQuickLook() throws {
        openIndexedSeededCodebase(analysis: .canned)

        let dismissButton = app.buttons["sourceViewer.dismissButton"]
        app.buttons["violation.viewSourceButton"].firstMatch.tap("View Source", until: dismissButton)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "QuickLookSheetOpen"
        attachment.lifetime = .keepAlways
        add(attachment)
        dismissButton.tapWhenReady("the Quick Look sheet's Done button")
    }
}
