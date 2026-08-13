import Foundation

/// Carries an incoming Handoff/Spotlight continuation from `AcaiRootScene`'s
/// `.onContinueUserActivity` down to `ProjectBrowserView`, which resolves it into a selection —
/// mirrors `QuickOpenPresenter`'s identical role for the `.commands` menu.
@MainActor
final class HandoffContinuationPresenter: ObservableObject {
    enum Target: Equatable {
        case diagram(UUID)
        case codebase(UUID)
        /// Identified by the tapped `CSSearchableItem`'s `uniqueIdentifier`, matching `QuickOpenEntry.id`.
        case spotlightItem(String)
    }

    @Published var pendingTarget: Target?
}
