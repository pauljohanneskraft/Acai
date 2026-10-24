import Foundation
import Testing
@testable import AcaiApp

@Suite("Renaming a sidebar row", .timeLimit(.minutes(1)))
struct SidebarRenameTests {
    @Test func beginningARenameSeedsTheCurrentName() {
        var rename = SidebarRename()
        let codebase = ProjectBrowserViewModel.Selection.codebase(UUID())

        rename.begin(codebase, currentName: "widgets")

        #expect(rename.row == codebase)
        #expect(rename.text == "widgets")
    }

    @Test func beginningAnotherRenameClosesTheOpenOne() {
        var rename = SidebarRename()
        let diagram = ProjectBrowserViewModel.Selection.generatedDiagram(UUID())
        let codebase = ProjectBrowserViewModel.Selection.codebase(UUID())

        rename.begin(diagram, currentName: "Overview")
        rename.text = "Overview v2"
        rename.begin(codebase, currentName: "widgets")

        #expect(rename.row == codebase)
        #expect(rename.text == "widgets")
    }

    @Test func finishingLeavesNoRowBeingRenamed() {
        var rename = SidebarRename()
        rename.begin(.freeformDiagram(UUID()), currentName: "Sketch")

        rename.finish()

        #expect(rename.row == nil)
    }
}
