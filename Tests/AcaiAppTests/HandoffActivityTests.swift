import Foundation
import Testing
@testable import AcaiApp

/// Guards the string-key contract between each activity's `configure(_:)` and `AcaiApp.swift`'s
/// continuation closures, which read the same keys back by literal string (no shared constant, so
/// a typo on either side would silently break Handoff with no compile error).
@Suite("Handoff activity configuration")
struct HandoffActivityTests {
    private func codebase() -> Codebase {
        Codebase(name: "Demo", directoryPath: "/tmp/demo")
    }

    @Test func codebaseActivityConfiguresTitleAndUserInfo() {
        let codebase = codebase()
        let activity = NSUserActivity(activityType: CodebaseHandoffActivity.activityType)
        CodebaseHandoffActivity(codebase: codebase).configure(activity)

        #expect(activity.title == codebase.name)
        #expect(activity.isEligibleForHandoff)
        #expect(activity.targetContentIdentifier == "codebase:\(codebase.id)")
        #expect(activity.userInfo?["codebaseID"] as? String == codebase.id.uuidString)
    }

    @Test func diagramActivityConfiguresTitleAndUserInfo() {
        let codebase = codebase()
        let diagram = GeneratedDiagram(name: "Modules", content: .packageDiagram, codebaseID: codebase.id)
        let activity = NSUserActivity(activityType: DiagramHandoffActivity.activityType)
        DiagramHandoffActivity(diagram: diagram, codebase: codebase).configure(activity)

        #expect(activity.title == diagram.name)
        #expect(activity.isEligibleForHandoff)
        #expect(activity.targetContentIdentifier == "generatedDiagram:\(diagram.id)")
        // Exact keys `AcaiApp.swift`'s continuation closures read back — see this suite's doc comment.
        #expect(activity.userInfo?["generatedDiagramID"] as? String == diagram.id.uuidString)
        #expect(activity.userInfo?["codebaseID"] as? String == codebase.id.uuidString)
    }
}
