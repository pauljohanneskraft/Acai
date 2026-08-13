import Foundation

/// Configures the `NSUserActivity` a codebase's detail screen advertises for Handoff — see
/// `DiagramHandoffActivity`'s doc comment for the same "only works when the codebase already
/// exists locally on both devices, no iCloud sync" limitation, which applies here identically.
struct CodebaseHandoffActivity {
    static let activityType = "de.kraftsoftware.acai.viewCodebase"

    let codebase: Codebase

    func configure(_ activity: NSUserActivity) {
        activity.title = codebase.name
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.targetContentIdentifier = "codebase:\(codebase.id)"
        activity.userInfo = ["codebaseID": codebase.id.uuidString]
    }
}
