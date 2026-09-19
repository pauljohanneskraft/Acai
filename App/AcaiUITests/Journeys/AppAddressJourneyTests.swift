import XCTest

/// `acai://` links open what they name, and a link to something that no longer exists says so.
@MainActor
final class AppAddressJourneyTests: UIJourneyTestCase {
    private let freeformDiagramID = "33333333-3333-3333-3333-333333333333"

    func testALinkOpensTheCodebaseOrDiagramItNames() {
        let browser = launchSeeded()
        browser.newProjectButton.waitOrFail("the project browser")

        browser.openLink("acai://codebase/\(seeded.codebaseID)")
        CodebaseDetailScreen(app: app).reindexButton.waitOrFail("the linked codebase's screen")

        browser.openLink("acai://diagram/\(freeformDiagramID)")
        FreeformDiagramScreen(app: app).openedIndicator.waitOrFail("the linked freeform diagram")
    }

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
