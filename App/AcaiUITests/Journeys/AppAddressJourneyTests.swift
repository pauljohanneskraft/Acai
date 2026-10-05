import XCTest

/// A link to something that no longer exists says so.
///
/// `openLink` relaunches the app on iOS, so this is the most launch-expensive journey in the suite
/// and every step it keeps has to earn a share of the 180s execution allowance that two launches
/// nearly exhaust. What it keeps is the presentation: a dead `acai://diagram/…` address raises an
/// alert, and that alert says which thing is gone. Dismissing it is SwiftUI's own behaviour, so the
/// OK tap and the disappearance it would be waited out with are not here.
///
/// The rest of the address surface is proven without a launch of its own — which address maps to
/// which destination by `AppAddressTests`, and that a live link really opens its destination by
/// `ScreenCatalogTests`, which reaches the seeded freeform diagram through `acai://diagram/…`
/// rather than by tapping.
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
        alert.buttons["OK"].waitOrFail("the error alert for a link to a deleted diagram")
        // macOS exposes an alert's message as the element's `value`, iOS as its `label`. The alert's
        // button resolves before its message does, so this waits rather than reading `exists` once.
        let expected = "The linked diagram no longer exists"
        alert.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected))
            .firstMatch
            .waitOrFail("the alert's message naming the deleted diagram")
    }
}
