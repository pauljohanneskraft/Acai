import XCTest

/// A link to something that no longer exists says so.
///
/// Only the failing half is here: `openLink` relaunches the app on iOS, and four launches put this
/// over its execution allowance on a cold iPad. What the other launches proved is covered without
/// them — which address maps to which destination by `AppAddressTests`, and that a live link really
/// opens its destination by `ScreenCatalogTests`, which reaches the seeded freeform diagram through
/// `acai://diagram/…` rather than by tapping.
@MainActor
final class AppAddressJourneyTests: UIJourneyTestCase {

    func testALinkToADeletedDiagramSaysSo() {
        let browser = launchSeeded()
        browser.newProjectButton.waitOrFail("the project browser")

        browser.openLink("acai://diagram/44444444-4444-4444-4444-444444444444")

        #if os(macOS)
        let alert = app.sheets
        #else
        let alert = app.alerts
        #endif
        let okButton = alert.buttons["OK"]
        okButton.waitOrFail("the error alert for a link to a deleted diagram")
        // macOS exposes an alert's message as the element's `value`, iOS as its `label`.
        let expected = "The linked diagram no longer exists"
        let message = alert.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected))
            .firstMatch
        XCTAssertTrue(message.exists, "The alert must say the linked diagram no longer exists.")
        okButton.tapWhenReady("the alert's OK button")
        okButton.waitForDisappearanceOrFail("the error alert")
    }
}
