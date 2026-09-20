import XCTest
#if os(iOS)

/// On iOS and iPadOS an export goes to the system share sheet, where Save to Files is one option.
@MainActor
final class ExportShareJourneyTests: UIJourneyTestCase {
    func testExportingAnImageSharesItAsAPNGFile() throws {
        let codebaseDetail = openIndexedSeededCodebase()
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
        diagram.typeNode(named: "Base").waitOrFail("the Base type node", timeout: .uiWork)

        let shareSheet = diagram.exportImage()
        shareSheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'PNG Image'")).firstMatch
            .waitOrFail("the shared file's PNG caption")

        // The share sheet has no Close button; it goes away by a tap outside it.
        app.dismissPopover(showing: shareSheet)
        shareSheet.waitForDisappearanceOrFail("the dismissed share sheet")
    }
}
#endif
