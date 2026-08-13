import Foundation

// Resolves an incoming Handoff/Spotlight continuation into a selection — carved out of
// `ProjectBrowserView`, matching how `+Repositories.swift`/`+SidebarRows.swift`/`+QuickOpen.swift`
// already split that screen's concerns into extensions.
extension ProjectBrowserView {
    func resolveHandoffContinuation(_ target: HandoffContinuationPresenter.Target?) {
        guard let target else { return }
        defer { handoffPresenter.pendingTarget = nil }
        switch target {
        case .diagram(let id):
            model.selection = .generatedDiagram(id)
        case .codebase(let id):
            model.selection = .codebase(id)
        case .spotlightItem(let identifier):
            Task { await resolveSpotlightTap(identifier: identifier) }
        }
    }

    /// Rebuilds Quick Open's entry list off the main actor to find the entry the tapped
    /// `CSSearchableItem` was indexed from, then applies it as a Quick Open row tap would.
    private func resolveSpotlightTap(identifier: String) async {
        let builder = QuickOpenIndexBuilder(
            projects: model.store.projects, artifacts: model.store.artifacts,
            generatedDiagrams: model.store.generatedDiagrams, freeformDiagrams: model.store.freeformDiagrams
        )
        guard let entry = await Task.detached(priority: .userInitiated, operation: {
            builder.entries().first { $0.id == identifier }
        }).value else { return }
        model.applyQuickOpenEntryDefault(entry)
    }
}
