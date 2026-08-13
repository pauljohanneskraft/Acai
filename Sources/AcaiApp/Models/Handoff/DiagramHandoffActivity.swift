import Foundation

/// Configures the `NSUserActivity` a generated-diagram screen advertises for Handoff. Meaningful
/// only when the codebase already exists locally on the continuing device too — this app has no
/// iCloud sync, so `ProjectBrowserView+Handoff.swift` simply no-ops when it isn't present there.
struct DiagramHandoffActivity {
    static let activityType = "de.kraftsoftware.acai.viewDiagram"

    let diagram: GeneratedDiagram
    let codebase: Codebase

    func configure(_ activity: NSUserActivity) {
        activity.title = diagram.name
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.targetContentIdentifier = "generatedDiagram:\(diagram.id)"
        activity.userInfo = [
            "generatedDiagramID": diagram.id.uuidString,
            "codebaseID": codebase.id.uuidString
        ]
    }
}
