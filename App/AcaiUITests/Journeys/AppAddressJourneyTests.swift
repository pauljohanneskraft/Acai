import XCTest

/// A link to something that no longer exists says so. Which address maps to which destination is
/// `AppAddressTests`; that a live link opens its destination is covered by `ScreenCatalogTests`.
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
        alert.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected))
            .firstMatch
            .waitOrFail("the alert's message naming the deleted diagram")
        okButton.tapWhenReady("the alert's OK button")
        okButton.waitForDisappearanceOrFail("the error alert")
    }
}
